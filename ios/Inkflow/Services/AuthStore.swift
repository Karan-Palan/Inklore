import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// The single source of truth for authentication. Owns the persisted session,
/// drives Apple / Google / email sign-in, refreshes tokens, and exposes the
/// signed-in state to the app. Session tokens are stored in the Keychain.
@Observable
@MainActor
final class AuthStore: NSObject {
  /// The current session, or nil when signed out.
  private(set) var session: AuthSession?
  /// True while restoring a persisted session on launch.
  private(set) var isRestoring = true
  /// True while a sign-in request is in flight.
  var isWorking = false
  /// The most recent user-facing error, if any.
  var errorMessage: String?

  var isSignedIn: Bool { session != nil }
  var user: AuthUser? { session?.user }

  // Raw nonce kept between requesting Apple auth and exchanging the token.
  private var pendingAppleNonce: String?
  private var webAuthSession: ASWebAuthenticationSession?

  // MARK: - Lifecycle

  /// Restore any saved session, refreshing it if the access token expired.
  func restore() async {
    defer { isRestoring = false }
    guard BackendConfig.isAuthReady else { return }
    guard let saved = AuthKeychain.load() else { return }
    if saved.isExpired {
      await refreshIfNeeded(saved)
    } else {
      session = saved
    }
  }

  private func refreshIfNeeded(_ saved: AuthSession) async {
    do {
      var refreshed = try await AuthClient.refresh(refreshToken: saved.refreshToken)
      // GoTrue's refresh response may omit user details; keep the saved identity.
      if refreshed.user.email == nil { refreshed.user = saved.user }
      persist(refreshed)
    } catch {
      // Refresh failed (revoked / expired) — drop to signed-out.
      AuthKeychain.clear()
      session = nil
    }
  }

  /// Returns a valid access token, refreshing first if needed. Used by callers
  /// that make authenticated requests.
  func validAccessToken() async -> String? {
    guard let current = session else { return nil }
    if current.isExpired { await refreshIfNeeded(current) }
    return session?.accessToken
  }

  // MARK: - Email / password

  func signIn(email: String, password: String) async {
    await run {
      let s = try await AuthClient.signIn(
        email: Self.clean(email), password: password)
      self.persist(s)
    }
  }

  func signUp(email: String, password: String) async {
    await run {
      let s = try await AuthClient.signUp(
        email: Self.clean(email), password: password)
      self.persist(s)
    }
  }

  // MARK: - Apple

  /// Builds the request for `SignInWithAppleButton`. Stores a fresh nonce.
  func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
    let nonce = Self.randomString()
    pendingAppleNonce = nonce
    request.requestedScopes = [.fullName, .email]
    request.nonce = Self.sha256(nonce)
  }

  /// Handles the result of `SignInWithAppleButton`.
  func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .failure(let error):
      // User cancellation is not an error worth surfacing.
      if (error as? ASAuthorizationError)?.code == .canceled { return }
      errorMessage = error.localizedDescription
    case .success(let auth):
      guard
        let credential = auth.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = credential.identityToken,
        let idToken = String(data: tokenData, encoding: .utf8)
      else {
        errorMessage = "Apple did not return a valid identity token."
        return
      }
      let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
        .compactMap { $0 }.joined(separator: " ")
      let nonce = pendingAppleNonce
      Task {
        await run {
          let s = try await AuthClient.signInWithApple(
            idToken: idToken, nonce: nonce, fullName: fullName)
          self.persist(s)
        }
      }
    }
  }

  // MARK: - Google (web OAuth + PKCE)

  func signInWithGoogle() {
    guard BackendConfig.isGoogleReady else {
      errorMessage = AuthClient.AuthError.notConfigured.errorDescription
      return
    }
    guard
      let url = AuthClient.authorizeURL(
        provider: "google", redirectTo: BackendConfig.redirectURL)
    else {
      errorMessage = "Could not start Google sign in."
      return
    }

    let session = ASWebAuthenticationSession(
      url: url, callbackURLScheme: BackendConfig.redirectScheme
    ) { [weak self] callbackURL, error in
      guard let self else { return }
      Task { @MainActor in
        self.handleOAuthCallback(callbackURL, error: error)
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    webAuthSession = session
    session.start()
  }

  private func handleOAuthCallback(_ url: URL?, error: Error?) {
    webAuthSession = nil
    if let error {
      if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
      errorMessage = error.localizedDescription
      return
    }
    guard let url,
      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      errorMessage = "Sign in was cancelled."
      return
    }
    if let serverError = comps.queryItems?.first(where: { $0.name == "error_description" })?.value {
      errorMessage = serverError.replacingOccurrences(of: "+", with: " ")
      return
    }
    guard
      let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
    else {
      errorMessage = "Google sign in did not complete."
      return
    }
    Task {
      await run {
        let s = try await AuthClient.exchangeCode(code, provider: "google")
        self.persist(s)
      }
    }
  }

  // MARK: - Sign out

  func signOut() {
    let token = session?.accessToken
    let refresh = session?.refreshToken
    AuthKeychain.clear()
    session = nil
    if let token {
      Task { await AuthClient.signOut(accessToken: token, refreshToken: refresh) }
    }
  }

  /// Clears the account locally and ends the server session. The local session
  /// is always cleared even if the server call fails, so the user is never left
  /// in a half-deleted state.
  func deleteAccount() async {
    isWorking = true
    defer { isWorking = false }
    let token = await validAccessToken()
    let refresh = session?.refreshToken
    if let token {
      await AuthClient.signOut(accessToken: token, refreshToken: refresh)
    }
    AuthKeychain.clear()
    session = nil
    errorMessage = nil
  }

  // MARK: - Helpers

  private func persist(_ session: AuthSession) {
    AuthKeychain.save(session)
    self.session = session
    errorMessage = nil
  }

  /// Runs an async auth operation with shared working/error handling.
  private func run(_ operation: @escaping () async throws -> Void) async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await operation()
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  private static func clean(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  // MARK: - PKCE / nonce crypto

  private static func randomString(length: Int = 64) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    return Data(bytes).base64URLEncoded()
  }

  private static func sha256(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - Presentation anchor for ASWebAuthenticationSession

extension AuthStore: ASWebAuthenticationPresentationContextProviding {
  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
    -> ASPresentationAnchor
  {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes
      let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
      return windowScene?.keyWindow ?? ASPresentationAnchor()
    }
  }
}

extension Data {
  /// Base64-URL encoding (no padding) used for PKCE verifier/challenge + nonce.
  func base64URLEncoded() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

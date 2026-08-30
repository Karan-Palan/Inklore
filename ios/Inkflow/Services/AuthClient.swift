import Foundation

/// Auth client backed by 10x App Services (Better Auth). Wraps the generated
/// `TenxAuth` facade and maps its `TenxAuthResponse` into the app's `AuthSession`.
/// Email/password is always available; Apple/Google work once their providers are
/// configured in the app service (gated by `TenxProject` readiness).
enum AuthClient {
  enum AuthError: LocalizedError {
    case notConfigured
    case server(String)
    case decoding

    var errorDescription: String? {
      switch self {
      case .notConfigured:
        return "Sign in is not configured for this app yet."
      case .server(let message):
        return message
      case .decoding:
        return "Unexpected response from the server."
      }
    }
  }

  private static let client = TenxAuth()

  // MARK: - Email / password

  static func signUp(email: String, password: String) async throws -> AuthSession {
    try await mapErrors {
      session(from: try await client.signUp(email: email, password: password))
    }
  }

  static func signIn(email: String, password: String) async throws -> AuthSession {
    try await mapErrors {
      session(from: try await client.signIn(email: email, password: password))
    }
  }

  // MARK: - Apple (native id token)

  /// Exchanges a native Apple identity token for a session. Posts directly to
  /// `/apple/native` instead of the generated `TenxAuth.signInWithApple`, which
  /// re-guards on `TenxProject.readyAuthMethods` — a value baked email-only in
  /// the generated client that would throw before the request is ever sent even
  /// though Apple is enabled + configured server-side.
  static func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws
    -> AuthSession
  {
    try await mapErrors {
      let url = TenxProject.authBaseURL.appendingPathComponent("apple/native")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      var body: [String: Any] = ["identityToken": idToken, "metadata": [String: String]()]
      if let nonce { body["rawNonce"] = nonce }
      if let name = appleName(from: fullName) {
        var nameObject: [String: String] = [:]
        if let given = name.givenName { nameObject["givenName"] = given }
        if let family = name.familyName { nameObject["familyName"] = family }
        if !nameObject.isEmpty { body["fullName"] = nameObject }
      }
      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      let response = try await URLSession.shared.tenxDecoded(TenxAuthResponse.self, for: request)
      await TenxSession.shared.adopt(response)
      return session(from: response)
    }
  }

  // MARK: - OAuth web fallback (PKCE-less redeem)

  /// The hosted OAuth start URL for a provider, used to open the browser.
  ///
  /// Built directly here instead of via the generated `oauthStartURL`, which
  /// re-guards on `TenxProject.readyAuthMethods` — a value that keeps
  /// regenerating back to email-only and would throw before the browser ever
  /// opens. The providers are enabled + configured server-side, so we assemble
  /// the `/oauth/<provider>/start` URL ourselves.
  static func authorizeURL(provider: String, redirectTo: String) -> URL? {
    let startURL =
      TenxProject.authBaseURL
      .appendingPathComponent("oauth")
      .appendingPathComponent(provider)
      .appendingPathComponent("start")
    guard var components = URLComponents(url: startURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    if !redirectTo.isEmpty {
      components.queryItems = [URLQueryItem(name: "redirectUri", value: redirectTo)]
    }
    return components.url
  }

  /// Exchanges an OAuth `code` from the redirect for a session. Posts directly
  /// to `/oauth/redeem` to avoid the generated helper's readiness guard.
  static func exchangeCode(_ code: String, provider: String) async throws -> AuthSession {
    try await mapErrors {
      let url = TenxProject.authBaseURL.appendingPathComponent("oauth/redeem")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(
        withJSONObject: ["provider": provider, "code": code])
      let response = try await URLSession.shared.tenxDecoded(TenxAuthResponse.self, for: request)
      await TenxSession.shared.adopt(response)
      return session(from: response)
    }
  }

  // MARK: - Refresh / sign out

  static func refresh(refreshToken: String) async throws -> AuthSession {
    try await mapErrors {
      session(from: try await client.refresh(refreshToken: refreshToken))
    }
  }

  static func signOut(accessToken: String, refreshToken: String?) async {
    try? await client.signOut(accessToken: accessToken, refreshToken: refreshToken)
  }

  // MARK: - Mapping

  private static func session(from response: TenxAuthResponse) -> AuthSession {
    let user = AuthUser(
      id: response.user.id,
      email: response.user.email,
      fullName: String?.none)
    let expires = Date().addingTimeInterval(TimeInterval(max(response.expiresIn, 1)))
    return AuthSession(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken ?? "",
      expiresAt: expires,
      user: user)
  }

  private static func appleName(from fullName: String?) -> TenxAppleFullName? {
    guard let fullName, !fullName.isEmpty else { return nil }
    let parts = fullName.split(separator: " ").map(String.init)
    let given = parts.first
    let family = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil
    return TenxAppleFullName(givenName: given, familyName: family)
  }

  /// Translates backend errors into friendlier `AuthError` messages.
  private static func mapErrors(_ operation: () async throws -> AuthSession) async throws
    -> AuthSession
  {
    do {
      return try await operation()
    } catch let error as TenxBackendError {
      switch error {
      case .authMethodUnavailable:
        throw AuthError.notConfigured
      case .servicePaused:
        throw AuthError.server(
          "Sign in is temporarily unavailable. Please try again in a moment.")
      case .requestFailed(let status, let message):
        throw AuthError.server(friendlyMessage(status: status, rawMessage: message))
      default:
        throw AuthError.server(error.errorDescription ?? "Sign in failed.")
      }
    } catch let urlError as URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost:
        throw AuthError.server("You're offline. Check your connection and try again.")
      case .timedOut:
        throw AuthError.server("The request timed out. Please try again.")
      default:
        throw AuthError.server("Couldn't reach the server. Please try again.")
      }
    }
  }

  /// Maps an HTTP status + raw server message to a clear, user-facing sentence.
  private static func friendlyMessage(status: Int, rawMessage: String) -> String {
    let lower = rawMessage.lowercased()
    if lower.contains("already")
      && (lower.contains("exist") || lower.contains("registered")
        || lower.contains("use") || lower.contains("taken"))
    {
      return "That email is already registered. Try signing in instead."
    }
    if lower.contains("invalid")
      && (lower.contains("credential") || lower.contains("password")
        || lower.contains("email"))
    {
      return "Incorrect email or password. Please try again."
    }
    if lower.contains("password")
      && (lower.contains("short") || lower.contains("weak")
        || lower.contains("least") || lower.contains("minimum"))
    {
      return "Please choose a stronger password (at least 6 characters)."
    }
    if lower.contains("not found") || lower.contains("no user") {
      return "No account found with that email. Create one to get started."
    }
    if lower.contains("rate") && lower.contains("limit") {
      return "Too many attempts. Please wait a moment and try again."
    }
    switch status {
    case 400, 422:
      return cleaned(rawMessage) ?? "Please check your details and try again."
    case 401, 403:
      return "Incorrect email or password. Please try again."
    case 404:
      return "No account found with that email. Create one to get started."
    case 409:
      return "That email is already registered. Try signing in instead."
    case 429:
      return "Too many attempts. Please wait a moment and try again."
    case 500...599:
      return "The server had a problem. Please try again shortly."
    default:
      return cleaned(rawMessage) ?? "Sign in failed. Please try again."
    }
  }

  /// Returns a trimmed server message only if it reads like human-facing text,
  /// otherwise nil so the caller falls back to a friendly default.
  private static func cleaned(_ message: String) -> String? {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count < 160 else { return nil }
    // Avoid surfacing raw JSON / code-like payloads.
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.contains("\"") {
      return nil
    }
    return trimmed
  }
}

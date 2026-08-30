import Foundation
import Security
import CryptoKit

public struct TenxAuth {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Generate a one-time nonce for native Sign in with Apple / Google. Pass
    /// `hashed` to the provider request (ASAuthorizationAppleIDRequest.nonce or
    /// the Google request's nonce) and the matching `raw` value to
    /// signInWithApple(rawNonce:) / signInWithGoogle(rawNonce:). The nonce binds
    /// the returned id_token to this specific sign-in so a captured token cannot
    /// be replayed — always use it for native sign-in.
    public static func makeSignInNonce() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = Data(bytes).base64EncodedString()
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    public func signUp(email: String, password: String) async throws -> TenxAuthResponse {
        try TenxProject.requireAuthMethodReady(.emailPassword)
        return try await postAuth("/sign-up/email", body: ["email": email, "password": password])
    }

    public func signIn(email: String, password: String) async throws -> TenxAuthResponse {
        try TenxProject.requireAuthMethodReady(.emailPassword)
        return try await postAuth("/sign-in/email", body: ["email": email, "password": password])
    }

    public func requestEmailCode(email: String) async throws -> TenxEmailOTPResponse {
        try TenxProject.requireAuthMethodReady(.emailOtp)
        return try await postAuth("/email-otp/request", body: ["email": email], as: TenxEmailOTPResponse.self)
    }

    public func verifyEmailCode(email: String, code: String) async throws -> TenxAuthResponse {
        try TenxProject.requireAuthMethodReady(.emailOtp)
        return try await postAuth("/email-otp/verify", body: ["email": email, "otp": code])
    }

    public func refresh(refreshToken: String) async throws -> TenxAuthResponse {
        try await postAuth("/refresh", body: ["refreshToken": refreshToken])
    }

    public func oauthStartURL(provider: String, redirectURI: String? = nil) throws -> URL {
        guard TenxProject.isAuthMethodReady(provider) else {
            throw TenxBackendError.authMethodUnavailable(provider)
        }
        let startURL = TenxProject.authBaseURL
            .appendingPathComponent("oauth")
            .appendingPathComponent(provider)
            .appendingPathComponent("start")
        guard var components = URLComponents(url: startURL, resolvingAgainstBaseURL: false) else {
            throw TenxBackendError.invalidResponse
        }
        if let redirectURI, !redirectURI.isEmpty {
            components.queryItems = [URLQueryItem(name: "redirectUri", value: redirectURI)]
        }
        guard let url = components.url else {
            throw TenxBackendError.invalidResponse
        }
        return url
    }

    public func redeemOAuthCode(provider: String, code: String) async throws -> TenxAuthResponse {
        guard TenxProject.isAuthMethodReady(provider) else {
            throw TenxBackendError.authMethodUnavailable(provider)
        }
        return try await postAuth("/oauth/redeem", body: ["provider": provider, "code": code])
    }

    public func signInWithGoogle(idToken: String, rawNonce: String? = nil, metadata: [String: String] = [:]) async throws -> TenxAuthResponse {
        try TenxProject.requireAuthMethodReady(.google)
        var body: [String: Any] = ["idToken": idToken, "metadata": metadata]
        body["rawNonce"] = rawNonce
        return try await postAuth("/google/native", body: body)
    }

    public func signInWithApple(
        identityToken: String,
        rawNonce: String? = nil,
        fullName: TenxAppleFullName? = nil,
        metadata: [String: String] = [:]
    ) async throws -> TenxAuthResponse {
        try TenxProject.requireAuthMethodReady(.apple)
        var body: [String: Any] = ["identityToken": identityToken, "metadata": metadata]
        body["rawNonce"] = rawNonce
        if let fullName {
            body["fullName"] = try Self.jsonObject(from: fullName)
        }
        return try await postAuth("/apple/native", body: body)
    }

    public func session(accessToken: String) async throws -> TenxAuthSession {
        var request = URLRequest(url: TenxProject.authBaseURL.appendingPathComponent("session"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        struct Response: Codable { let session: TenxAuthSession }
        return try await session.tenxDecoded(Response.self, for: request).session
    }

    public func signOut(accessToken: String, refreshToken: String? = nil) async throws {
        var request = URLRequest(url: TenxProject.authBaseURL.appendingPathComponent("sign-out"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [:]
        body["refreshToken"] = refreshToken
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.tenxData(for: request)
    }

    /// Permanently delete the signed-in user's account and data (required by
    /// App Store Guideline for any app with account creation). Pass
    /// the account's `password` for a credential (email/password) user when the
    /// session may not be fresh; OAuth users can omit it.
    public func deleteAccount(accessToken: String, refreshToken: String? = nil, password: String? = nil) async throws {
        var request = URLRequest(url: TenxProject.authBaseURL.appendingPathComponent("delete-account"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [:]
        body["refreshToken"] = refreshToken
        body["password"] = password
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.tenxData(for: request)
    }

    private func postAuth(_ path: String, body: [String: Any]) async throws -> TenxAuthResponse {
        try await postAuth(path, body: body, as: TenxAuthResponse.self)
    }

    private func postAuth<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: TenxProject.authBaseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.tenxDecoded(T.self, for: request)
    }

    private static func jsonObject<T: Encodable>(from value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}

/// Persists the signed-in session and always hands back a *valid* access
/// token, transparently refreshing it before it expires. Access tokens live
/// ~60 minutes; route every authenticated request through
/// `TenxSession.shared.validAccessToken()` so a session never dies mid-use
/// and surfaces as "connection lost".
///
/// This session is the SINGLE source of truth for both the tokens AND whether
/// the user is signed in. Sign in via the `signIn`/`signUp` helpers here (or
/// call `adopt(_:)` after any `TenxAuth` sign-in / OAuth redeem) so the tokens
/// are Keychain-persisted and survive relaunch. NEVER copy the tokens into your
/// own app state and NEVER track sign-in with a separate persisted boolean:
/// a "signedIn" flag that outlives the in-memory tokens makes a relaunched app
/// skip sign-in yet hold no token, so every authenticated call and the realtime
/// socket fail with "connection lost". Gate authenticated UI on `isSignedIn`.
public actor TenxSession {
    public static let shared = TenxSession()

    private let auth: TenxAuth
    private let store: TenxSessionStore
    private let expiryLeewaySeconds: TimeInterval = 60

    private var accessToken: String?
    private var refreshTokenValue: String?
    private var expiresAt: Date?
    private var refreshTask: Task<TenxAuthResponse, Error>?

    public init(auth: TenxAuth = TenxAuth(), store: TenxSessionStore = TenxKeychainSessionStore()) {
        self.auth = auth
        self.store = store
        if let stored = store.load() {
            accessToken = stored["accessToken"] as? String
            refreshTokenValue = stored["refreshToken"] as? String
            if let timestamp = stored["expiresAt"] as? TimeInterval {
                expiresAt = Date(timeIntervalSince1970: timestamp)
            }
        }
    }

    public var isSignedIn: Bool {
        refreshTokenValue != nil || accessToken != nil
    }

    /// Store the tokens from a sign-in / sign-up / refresh / OAuth response.
    public func adopt(_ response: TenxAuthResponse) {
        accessToken = response.accessToken
        if let refreshed = response.refreshToken, !refreshed.isEmpty {
            refreshTokenValue = refreshed
        }
        expiresAt = Date().addingTimeInterval(TimeInterval(max(response.expiresIn, 0)))
        persist()
    }

    /// Email/password sign-in that ALSO persists the session (preferred over
    /// calling `TenxAuth().signIn` yourself, which leaves persistence to you).
    @discardableResult
    public func signIn(email: String, password: String) async throws -> TenxAuthResponse {
        let response = try await auth.signIn(email: email, password: password)
        adopt(response)
        return response
    }

    /// Email/password sign-up that ALSO persists the session.
    @discardableResult
    public func signUp(email: String, password: String) async throws -> TenxAuthResponse {
        let response = try await auth.signUp(email: email, password: password)
        adopt(response)
        return response
    }

    /// A valid access token, refreshing first if it's missing or within the
    /// leeway window of expiring.
    public func validAccessToken() async throws -> String {
        if let token = accessToken, let expiry = expiresAt,
           expiry.timeIntervalSinceNow > expiryLeewaySeconds {
            return token
        }
        return try await refresh()
    }

    /// Force a refresh now. Concurrent callers share a single in-flight
    /// refresh so a rotating refresh token is never spent twice.
    @discardableResult
    public func refresh() async throws -> String {
        let response: TenxAuthResponse
        if let existing = refreshTask {
            response = try await existing.value
        } else {
            guard let currentRefresh = refreshTokenValue else {
                throw TenxBackendError.notSignedIn
            }
            let auth = self.auth
            let task = Task<TenxAuthResponse, Error> {
                try await auth.refresh(refreshToken: currentRefresh)
            }
            refreshTask = task
            defer { refreshTask = nil }
            response = try await task.value
        }
        adopt(response)
        return response.accessToken
    }

    /// Clear the local session and best-effort revoke it server-side.
    public func signOut() async {
        let token = accessToken
        let currentRefresh = refreshTokenValue
        accessToken = nil
        refreshTokenValue = nil
        expiresAt = nil
        refreshTask?.cancel()
        refreshTask = nil
        persist()
        if let token {
            try? await auth.signOut(accessToken: token, refreshToken: currentRefresh)
        }
    }

    /// Permanently delete the signed-in user's account + data, then clear the
    /// local session. Required by App Store Guideline for any app with
    /// account creation. Pass `password` for a credential user (needed when the
    /// session is not fresh). Throws if the delete fails (wrong password / not
    /// signed in) so the caller can surface the error and stay signed in; the
    /// local session is cleared only on success.
    public func deleteAccount(password: String? = nil) async throws {
        let token = try await validAccessToken()
        try await auth.deleteAccount(accessToken: token, refreshToken: refreshTokenValue, password: password)
        accessToken = nil
        refreshTokenValue = nil
        expiresAt = nil
        refreshTask?.cancel()
        refreshTask = nil
        persist()
    }

    private func persist() {
        if accessToken == nil, refreshTokenValue == nil {
            store.clear()
            return
        }
        var stored: [String: Any] = [:]
        stored["accessToken"] = accessToken
        stored["refreshToken"] = refreshTokenValue
        if let expiresAt {
            stored["expiresAt"] = expiresAt.timeIntervalSince1970
        }
        store.save(stored)
    }
}

/// Persistence backend for `TenxSession`. Implementations MUST scope their
/// storage per backend (see `TenxSessionStore.accountScope`) so two generated
/// SDKs living in one app binary (e.g. a preview build and a prod build) can
/// never read or overwrite each other's tokens.
public protocol TenxSessionStore: Sendable {
    func load() -> [String: Any]?
    func save(_ payload: [String: Any])
    func clear()
}

/// A stable per-backend scope derived from the project API URL, so the
/// storage slot is unique to this generated SDK's environment.
public enum TenxSessionScope {
    public static var account: String {
        let source = TenxProject.projectAPIURL.absoluteString
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let sanitized = String(source.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return "tenx.session.v1.\(sanitized)"
    }
}

/// Keychain-backed, tenant-scoped session store. Tokens are stored in the
/// Keychain (not plaintext UserDefaults) under a per-backend account key, so
/// they survive app restarts, aren't world-readable in the app container, and
/// don't collide across environments sharing one binary.
public struct TenxKeychainSessionStore: TenxSessionStore {
    private let service = "tenx.session"
    private let account: String

    public init(account: String = TenxSessionScope.account) {
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> [String: Any]? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    public func save(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery.merge(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
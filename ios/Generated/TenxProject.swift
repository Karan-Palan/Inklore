import Foundation

public enum TenxProject {
    // The released iOS app talks to the public backend. Scheme environment
    // variables are available only to local Debug runs, so the compiled
    // fallback must also be the production API for TestFlight and App Store.
    public static let projectAPIURL = resolvedURL("TENX_PROJECT_API_URL", fallback: "https://readsync-api.vercel.app")
    public static let authBaseURL = resolvedURL("TENX_AUTH_BASE_URL", fallback: "https://prv-8fbe26fba35f456c.preview.10x.app/auth")
    public static let storageBaseURL = resolvedURL("TENX_STORAGE_BASE_URL", fallback: "https://prv-8fbe26fba35f456c.preview.10x.app/storage")
    public static let requestTimeoutInterval: TimeInterval = 20
public static let dataAPIURL: URL? = resolvedOptionalURL("TENX_DATA_API_URL", fallback: "https://ep-small-dawn-atpg7xjo.apirest.c-9.us-east-1.aws.neon.tech/neondb/rest/v1")
public static let jwksURL: URL? = nil
public static let audience: String? = nil
public static let appServiceID: String? = nil
public static let generatedClientHash: String? = nil
public static let storageBuckets: [String] = ["photos", "attachments", "book_files"]
    public static let readyAuthMethods: Set<String> = Set(["emailPassword"])

    public enum AuthMethod: String, Sendable {
        case emailPassword
        case emailOtp
        case apple
        case google
        case github
    }

    public static func isAuthMethodReady(_ method: AuthMethod) -> Bool {
        readyAuthMethods.contains(method.rawValue)
    }

    public static func isAuthMethodReady(_ method: String) -> Bool {
        readyAuthMethods.contains(method)
    }

    public static func requireAuthMethodReady(_ method: AuthMethod) throws {
        guard isAuthMethodReady(method) else {
            throw TenxBackendError.authMethodUnavailable(method.rawValue)
        }
    }

    // Never force-unwrap into a `static let`: an empty/invalid configured
    // value would crash the app on first access at launch. Prefer a valid
    // runtime override, then the (generation-validated) fallback, then a
    // last-resort placeholder that always parses so the app degrades to
    // failing requests instead of crashing.
    private static func resolvedURL(_ key: String, fallback: String) -> URL {
        if let override = overrideValue(key), let url = URL(string: override) {
            return url
        }
        if let url = URL(string: fallback) {
            return url
        }
        return URL(string: "https://unconfigured.tenx.invalid")!
    }

    private static func resolvedOptionalURL(_ key: String, fallback: String?) -> URL? {
        guard let configured = overrideValue(key) ?? fallback else { return nil }
        return URL(string: configured)
    }

    private static func overrideValue(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

public struct TenxServicePaused: Error, LocalizedError, Sendable {
    public let statusCode: Int
    public let code: String?
    public let message: String
    public let reason: String?
    public let retryable: Bool

    public var errorDescription: String? {
        "Service paused with status \(statusCode): \(message)"
    }
}

public enum TenxBackendError: Error, LocalizedError {
    case missingDataAPIURL
    case authMethodUnavailable(String)
    case invalidResponse
    case servicePaused(TenxServicePaused)
    case requestFailed(Int, String)
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .missingDataAPIURL:
            return "The 10x data API URL is not configured for this project."
        case .authMethodUnavailable(let method):
            return "The auth method '\(method)' is not configured for this project."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .servicePaused(let state):
            return state.errorDescription
        case .requestFailed(let status, let message):
            return "Backend request failed with status \(status): \(message)"
        case .notSignedIn:
            return "You're signed out. Sign in again to continue."
        }
    }
}

struct TenxFlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == TenxFlexibleCodingKey {
    func decodeString(_ key: String, _ fallbackKey: String? = nil, defaultValue: String? = nil) throws -> String {
        if let value = try decodeOptionalString(key, fallbackKey) {
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw DecodingError.keyNotFound(
            TenxFlexibleCodingKey(key),
            .init(codingPath: codingPath, debugDescription: "Missing required key '\(key)'")
        )
    }

    func decodeOptionalString(_ key: String, _ fallbackKey: String? = nil) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: TenxFlexibleCodingKey(key)) {
            return value
        }
        if let fallbackKey {
            return try decodeIfPresent(String.self, forKey: TenxFlexibleCodingKey(fallbackKey))
        }
        return nil
    }

    func decodeInt(_ key: String, _ fallbackKey: String? = nil, defaultValue: Int? = nil) throws -> Int {
        if let value = try decodeOptionalInt(key, fallbackKey) {
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw DecodingError.keyNotFound(
            TenxFlexibleCodingKey(key),
            .init(codingPath: codingPath, debugDescription: "Missing required key '\(key)'")
        )
    }

    func decodeOptionalInt(_ key: String, _ fallbackKey: String? = nil) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: TenxFlexibleCodingKey(key)) {
            return value
        }
        if let fallbackKey {
            return try decodeIfPresent(Int.self, forKey: TenxFlexibleCodingKey(fallbackKey))
        }
        return nil
    }

    func decodeOptionalBool(_ key: String, _ fallbackKey: String? = nil) throws -> Bool? {
        if let value = try decodeIfPresent(Bool.self, forKey: TenxFlexibleCodingKey(key)) {
            return value
        }
        if let fallbackKey {
            return try decodeIfPresent(Bool.self, forKey: TenxFlexibleCodingKey(fallbackKey))
        }
        return nil
    }

    func decodeValue<T: Decodable>(_ type: T.Type, _ key: String, _ fallbackKey: String? = nil) throws -> T {
        if let value = try decodeIfPresent(type, forKey: TenxFlexibleCodingKey(key)) {
            return value
        }
        if let fallbackKey,
           let value = try decodeIfPresent(type, forKey: TenxFlexibleCodingKey(fallbackKey)) {
            return value
        }
        throw DecodingError.keyNotFound(
            TenxFlexibleCodingKey(key),
            .init(codingPath: codingPath, debugDescription: "Missing required key '\(key)'")
        )
    }

    func decodeOptionalValue<T: Decodable>(_ type: T.Type, _ key: String, _ fallbackKey: String? = nil) throws -> T? {
        if let value = try decodeIfPresent(type, forKey: TenxFlexibleCodingKey(key)) {
            return value
        }
        if let fallbackKey {
            return try decodeIfPresent(type, forKey: TenxFlexibleCodingKey(fallbackKey))
        }
        return nil
    }
}

public struct TenxAuthUser: Codable, Sendable, Identifiable {
    public let id: String
    public let email: String?
    public let emailVerified: Bool?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        id = try container.decodeString("id")
        email = try container.decodeOptionalString("email")
        emailVerified = try container.decodeOptionalBool("email_verified", "emailVerified")
    }
}

public struct TenxAuthSession: Codable, Sendable {
    public let id: String?
    public let expiresAt: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        id = try container.decodeOptionalString("id")
        expiresAt = try container.decodeOptionalString("expires_at", "expiresAt")
    }
}

public struct TenxAuthResponse: Codable, Sendable {
    public let tokenType: String
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let user: TenxAuthUser
    public let session: TenxAuthSession?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        tokenType = try container.decodeString("token_type", "tokenType", defaultValue: "Bearer")
        accessToken = try container.decodeString("access_token", "accessToken")
        // Managed responses always include `expires_in`, but if a response
        // ever omits it (or reports <= 0), fall back to a conservative TTL
        // instead of 0. A 0 TTL makes the token look already-expired, so
        // TenxSession would force a refresh round-trip on every single call.
        // Default to the safe fallback (not 0) so even a read before the clamp
        // below can never produce an already-expired 0 TTL / refresh storm.
        let decodedExpiresIn = try container.decodeInt("expires_in", "expiresIn", defaultValue: 3000)
        expiresIn = decodedExpiresIn > 0 ? decodedExpiresIn : 3000
        refreshToken = try container.decodeOptionalString("refresh_token", "refreshToken")
        user = try container.decodeValue(TenxAuthUser.self, "user")
        session = try container.decodeOptionalValue(TenxAuthSession.self, "session")
    }
}

public struct TenxEmailOTPResponse: Codable, Sendable {
    public let status: String
    public let expiresInSeconds: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        status = try container.decodeString("status")
        expiresInSeconds = try container.decodeInt("expires_in_seconds", "expiresInSeconds", defaultValue: 0)
    }
}

public struct TenxAppleFullName: Codable, Sendable {
    public let givenName: String?
    public let familyName: String?
    public let middleName: String?
    public let nickname: String?

    public init(givenName: String? = nil, familyName: String? = nil, middleName: String? = nil, nickname: String? = nil) {
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.nickname = nickname
    }
}

extension URLSession {
    func tenxDecoded<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = TenxProject.requestTimeoutInterval
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TenxBackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.tenxBackendError(statusCode: http.statusCode, data: data)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func tenxData(for request: URLRequest, retryingTransientJWKMiss: Bool = false) async throws -> Data {
        var request = request
        request.timeoutInterval = TenxProject.requestTimeoutInterval
        let maximumAttempts = retryingTransientJWKMiss ? 8 : 1
        for attempt in 0..<maximumAttempts {
            let (data, response) = try await data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TenxBackendError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                if retryingTransientJWKMiss,
                   http.statusCode == 400,
                   Self.isTransientNeonJWKMiss(data),
                   attempt < maximumAttempts - 1 {
                    try await Task.sleep(nanoseconds: UInt64(min(1_500_000_000, 200_000_000 * (attempt + 1))))
                    continue
                }
                throw Self.tenxBackendError(statusCode: http.statusCode, data: data)
            }
            return data
        }
        throw TenxBackendError.invalidResponse
    }

    private static func tenxBackendError(statusCode: Int, data: Data) -> TenxBackendError {
        let object = tenxErrorObject(from: data)
        let message = tenxString(object, keys: ["message", "error_description", "error", "detail"])
            ?? String(data: data, encoding: .utf8)
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        if isTenxServicePaused(statusCode: statusCode, object: object) {
            let state = TenxServicePaused(
                statusCode: statusCode,
                code: tenxString(object, keys: ["code", "error_code", "errorCode"]),
                message: message,
                reason: tenxString(object, keys: ["paused_reason", "pausedReason", "reason", "cap_status", "capStatus", "code"]),
                retryable: tenxBool(object, keys: ["retryable"]) ?? true
            )
            return .servicePaused(state)
        }
        return .requestFailed(statusCode, message)
    }

    private static func isTenxServicePaused(statusCode: Int, object: [String: Any]) -> Bool {
        if statusCode == 423 {
            return true
        }
        if tenxBool(object, keys: ["paused"]) == true {
            return true
        }
        let markers = [
            tenxString(object, keys: ["code", "error_code", "errorCode"]),
            tenxString(object, keys: ["paused_reason", "pausedReason", "reason"]),
            tenxString(object, keys: ["cap_status", "capStatus"]),
            tenxString(object, keys: ["status"]),
            tenxString(object, keys: ["message", "error", "detail"]),
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if markers.contains("paused") || markers.contains("pause") || markers.contains("cap_reached") || markers.contains("spend_cap") {
            return true
        }
        return statusCode == 429 && (markers.contains("cap") || markers.contains("limit"))
    }

    private static func tenxErrorObject(from data: Data) -> [String: Any] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        var object = parsed as? [String: Any] ?? [:]
        if let detail = object["detail"] as? [String: Any] {
            for (key, value) in detail {
                object[key] = value
            }
        } else if let detail = object["detail"] as? String,
                  object["message"] == nil {
            object["message"] = detail
        }
        return object
    }

    private static func tenxString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func tenxBool(_ object: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = object[key] as? Bool {
                return value
            }
        }
        return nil
    }

    private static func isTransientNeonJWKMiss(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return false
        }
        return message == "jwk not found"
    }
}

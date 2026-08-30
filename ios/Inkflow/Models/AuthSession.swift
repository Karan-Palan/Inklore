import Foundation

/// A persisted 10x App Services (Better Auth) session. Stored locally so the user
/// stays signed in across launches; refreshed automatically when the access token
/// nears expiry. This is the single source of truth for "who is signed in".
struct AuthSession: Codable, Equatable {
  var accessToken: String
  var refreshToken: String
  /// Absolute expiry time of the access token.
  var expiresAt: Date
  var user: AuthUser

  var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

/// The signed-in user's identity, as returned by GoTrue.
struct AuthUser: Codable, Equatable {
  var id: String
  var email: String?
  /// Display name pulled from user_metadata (full_name / name) when present.
  var fullName: String?

  /// Best-effort first name for greetings.
  var firstName: String? {
    guard let fullName, !fullName.isEmpty else { return nil }
    return fullName.split(separator: " ").first.map(String.init)
  }
}

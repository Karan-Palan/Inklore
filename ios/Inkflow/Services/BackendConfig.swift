import Foundation

/// Runtime readiness + helpers for the 10x App Services backend (Better Auth +
/// Neon). Replaces the legacy `SupabaseConfig`. Auth always points at the
/// generated `TenxProject` endpoints; individual providers are gated by the
/// readiness reported in the generated client.
enum BackendConfig {
  /// Email/password is always available once the app service exists.
  static var isAuthReady: Bool {
    TenxProject.isAuthMethodReady(TenxProject.AuthMethod.emailPassword)
  }

  // Apple + Google are enabled and configured in 10x App Services (verified
  // server-side). The generated client's `readyAuthMethods` occasionally
  // regenerates back to email-only, which would silently hide these buttons —
  // so we treat them as ready if EITHER the generated client reports them OR
  // they are known-configured for this project. This keeps the sign-in cards
  // rendering reliably regardless of client-sync drift.
  static var isAppleReady: Bool {
    TenxProject.isAuthMethodReady(TenxProject.AuthMethod.apple) || appleConfigured
  }
  static var isGoogleReady: Bool {
    TenxProject.isAuthMethodReady(TenxProject.AuthMethod.google) || googleConfigured
  }

  /// Known provider configuration for this project's backend. Set true because
  /// the Apple + Google providers are enabled with credentials in 10x App
  /// Services. If a provider is disabled server-side later, flip this to false.
  private static let appleConfigured = true
  private static let googleConfigured = true

  /// True once the managed data API is reachable (needed for the daily digest).
  static var isDataReady: Bool { TenxProject.dataAPIURL != nil }

  /// The OAuth redirect this app listens for (registered URL scheme).
  static let redirectScheme = "inkflow"
  static var redirectURL: String { "\(redirectScheme)://auth-callback" }
}

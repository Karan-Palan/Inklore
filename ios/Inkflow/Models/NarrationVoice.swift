import AVFoundation
import Foundation

/// A selectable narration voice backed by a real installed `AVSpeechSynthesisVoice`.
/// We surface every English voice the device has, grouped by region and labeled
/// with quality + gender so the picker feels like a real cast of narrators —
/// not just the single default "Rishi" voice.
struct NarrationVoice: Identifiable, Hashable {
  let id: String  // AVSpeechSynthesisVoice.identifier
  let displayName: String
  let languageCode: String
  let regionName: String
  let gender: String
  let quality: AVSpeechSynthesisVoiceQuality
  let isPremium: Bool

  var qualityLabel: String {
    switch quality {
    case .premium: return "Premium"
    case .enhanced: return "Enhanced"
    default: return "Standard"
    }
  }

  /// Short subtitle for the picker row, e.g. "Female · Enhanced".
  var subtitle: String {
    [gender, qualityLabel].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  /// Resolve back to the live system voice for synthesis.
  var avVoice: AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice(identifier: id) }
}

/// A server-curated ElevenLabs voice. Only public display metadata and the
/// provider preview URL reach the device; the ElevenLabs credential never does.
struct ElevenLabsVoice: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let name: String
  let category: String?
  let voiceDescription: String?
  let previewURLString: String?
  let labels: [String: String]

  enum CodingKeys: String, CodingKey {
    case id = "voice_id"
    case name
    case category
    case voiceDescription = "description"
    case previewURLString = "preview_url"
    case labels
  }

  var previewURL: URL? {
    guard let previewURLString else { return nil }
    return URL(string: previewURLString)
  }

  var subtitle: String {
    let details = [labels["gender"], labels["accent"], labels["age"]]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
    if !details.isEmpty { return details.joined(separator: " · ") }
    return category?.capitalized ?? "ElevenLabs voice"
  }
}

/// Backend contracts for the cloud voice catalogue and bounded narration route.
/// Keeping these client models here avoids exposing an API key or provider URL
/// anywhere in the iOS project.
enum ElevenLabsCatalogService {
  private struct Response: Decodable {
    let provider: String
    let voices: [ElevenLabsVoice]
  }

  static func loadVoices() async throws -> [ElevenLabsVoice] {
    let response = try await BackendClient().get(Response.self, path: "/api/v1/voices")
    guard response.provider == "elevenlabs" else {
      throw VoiceServiceError.unsupportedProvider
    }
    return response.voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

enum VoiceServiceError: LocalizedError {
  case unsupportedProvider

  var errorDescription: String? {
    switch self {
    case .unsupportedProvider: return "The voice service returned an unsupported catalogue."
    }
  }
}

struct CloudNarrationAlignment: Decodable, Sendable {
  let characters: [String]
  let characterStartTimes: [Double]
  let characterEndTimes: [Double]

  enum CodingKeys: String, CodingKey {
    case characters
    case characterStartTimes = "character_start_times_seconds"
    case characterEndTimes = "character_end_times_seconds"
  }
}

struct CloudNarrationResponse: Decodable, Sendable {
  let audioBase64: String
  let alignment: CloudNarrationAlignment?
  let normalizedAlignment: CloudNarrationAlignment?
  let voiceID: String

  enum CodingKeys: String, CodingKey {
    case audioBase64 = "audio_base64"
    case alignment
    case normalizedAlignment = "normalized_alignment"
    case voiceID = "voice_id"
  }
}

enum CloudNarrationService {
  private struct Request: Encodable {
    let text: String
    let voice_id: String
  }

  /// A dedicated, bounded session turns a stalled serverless/provider request
  /// into a recoverable fallback instead of an indefinitely spinning player.
  private static let narrationSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 50
    configuration.timeoutIntervalForResource = 55
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }()

  static func narrate(text: String, voiceID: String) async throws -> CloudNarrationResponse {
    try await BackendClient(session: narrationSession).send(
      CloudNarrationResponse.self,
      path: "/api/v1/narration",
      body: Request(text: text, voice_id: voiceID))
  }
}

/// Builds and caches the catalog of installed voices.
enum VoiceCatalog {
  /// Persisted user choice key.
  static let preferenceKey = "inkflow.preferredVoiceID"
  private static let providerPreferenceKey = "inkflow.preferredVoiceProvider"
  private static let elevenLabsPreferenceKey = "inkflow.preferredElevenLabsVoice"

  /// All English narration voices on this device, sorted best-quality first.
  /// We exclude Apple's "novelty" voices (Bells, Bubbles, Zarvox, …) and the
  /// low-fidelity Eloquence voices because they are robotic and unclear — only
  /// the natural, intelligible narrator voices are surfaced.
  static func englishVoices() -> [NarrationVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") }
      .filter { isClear($0) }
      .map(makeVoice)
      .sorted {
        if $0.quality.rawValue != $1.quality.rawValue {
          return $0.quality.rawValue > $1.quality.rawValue
        }
        return $0.displayName < $1.displayName
      }
  }

  /// Names of Apple's gimmick/novelty voices that sound robotic or distorted and
  /// should never be offered as a book narrator.
  private static let noveltyNames: Set<String> = [
    "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos",
    "Good News", "Jester", "Organ", "Superstar", "Trinoids", "Whisper",
    "Wobble", "Zarvox", "Junior", "Ralph", "Kathy", "Fred", "Grandma",
    "Grandpa", "Rocko", "Shelley", "Sandy", "Flo", "Eddy", "Reed",
  ]

  private static func isClear(_ v: AVSpeechSynthesisVoice) -> Bool {
    let id = v.identifier.lowercased()
    if id.contains("eloquence") { return false }
    if noveltyNames.contains(v.name) { return false }
    return true
  }

  /// Voices grouped by spoken region (United States, United Kingdom, …) for a
  /// sectioned picker.
  static func grouped() -> [(region: String, voices: [NarrationVoice])] {
    let groups = Dictionary(grouping: englishVoices(), by: \.regionName)
    return
      groups
      .map { (region: $0.key, voices: $0.value) }
      .sorted { $0.region < $1.region }
  }

  /// The user's preferred voice, falling back to the best available.
  static func preferred() -> NarrationVoice? {
    let all = englishVoices()
    if let saved = UserDefaults.standard.string(forKey: preferenceKey),
      let match = all.first(where: { $0.id == saved })
    {
      return match
    }
    return all.first
  }

  static func savePreference(_ voice: NarrationVoice) {
    UserDefaults.standard.set(voice.id, forKey: preferenceKey)
    UserDefaults.standard.set("system", forKey: providerPreferenceKey)
  }

  static func preferredElevenLabsVoice() -> ElevenLabsVoice? {
    guard UserDefaults.standard.string(forKey: providerPreferenceKey) == "elevenlabs",
      let data = UserDefaults.standard.data(forKey: elevenLabsPreferenceKey)
    else { return nil }
    return try? JSONDecoder().decode(ElevenLabsVoice.self, from: data)
  }

  static func savePreference(_ voice: ElevenLabsVoice) {
    guard let data = try? JSONEncoder().encode(voice) else { return }
    UserDefaults.standard.set(data, forKey: elevenLabsPreferenceKey)
    UserDefaults.standard.set("elevenlabs", forKey: providerPreferenceKey)
  }

  private static func makeVoice(_ v: AVSpeechSynthesisVoice) -> NarrationVoice {
    NarrationVoice(
      id: v.identifier,
      displayName: v.name,
      languageCode: v.language,
      regionName: regionName(for: v.language),
      gender: genderLabel(v.gender),
      quality: v.quality,
      isPremium: v.quality == .premium
    )
  }

  private static func genderLabel(_ gender: AVSpeechSynthesisVoiceGender) -> String {
    switch gender {
    case .male: return "Male"
    case .female: return "Female"
    default: return ""
    }
  }

  private static func regionName(for language: String) -> String {
    let locale = Locale(identifier: language)
    if let region = locale.region?.identifier,
      let name = Locale.current.localizedString(forRegionCode: region)
    {
      return name
    }
    return language.uppercased()
  }
}

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

/// Builds and caches the catalog of installed voices.
enum VoiceCatalog {
  /// Persisted user choice key.
  static let preferenceKey = "readsync.preferredVoiceID"

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

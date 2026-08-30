import AVFoundation
import Foundation
import SwiftUI

/// Real on-device narration of a book's text using AVSpeechSynthesizer. Picks a
/// user-selectable voice from the device's installed cast, tracks the spoken
/// word range for karaoke-style highlighting, and exposes play / pause / skip /
/// speed / pitch / sleep-timer controls.
///
/// NOTE: This is genuine text-to-speech of the actual book — not a mock. The same
/// interface could front a neural cloud TTS later for fully human narration.
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()

  /// Full text being narrated.
  private(set) var fullText: String = ""
  /// Global character offset where the current utterance starts.
  private var utteranceStart: Int = 0
  /// End of the small utterance currently queued with AVSpeechSynthesizer.
  private var utteranceEnd: Int = 0
  private var restartTask: Task<Void, Never>?

  // AVSpeechSynthesizer becomes unreliable with a book-sized utterance. Small
  // sentence-aware chunks keep memory bounded and allow a cancelled/paused
  // narration to resume without rebuilding the entire book.
  private let maximumUtteranceLength = 12_000

  // Observable state for the UI.
  var isPlaying = false
  var rate: Float = AVSpeechUtteranceDefaultSpeechRate
  var pitch: Float = 1.0
  /// Global range of the word currently being spoken (for highlighting).
  var spokenWordRange: NSRange?
  /// Global character offset of the reading head.
  var charOffset: Int = 0
  /// Live amplitude 0...1 driving the waveform while speaking.
  var level: Double = 0

  /// Currently selected narration voice.
  var voice: NarrationVoice?

  // Sleep timer.
  var sleepTimerMinutes: Int?  // nil = off
  private var sleepDeadline: Date?
  private var tickTimer: Timer?

  /// Retained synthesizer for voice previews. A local synthesizer would be
  /// deallocated as soon as `preview(_:)` returns, silencing the sample.
  private let previewSynth = AVSpeechSynthesizer()

  override init() {
    super.init()
    synthesizer.delegate = self
    voice = VoiceCatalog.preferred()
  }

  /// Configure the narrator with text and a starting offset.
  func load(text: String, startOffset: Int) {
    stop()
    fullText = text
    charOffset = min(max(0, startOffset), (text as NSString).length)
    utteranceStart = charOffset
    utteranceEnd = charOffset
  }

  var voiceName: String { voice?.displayName ?? "System voice" }

  /// Selects a new voice, persists it, and restarts speech mid-stream if playing.
  func selectVoice(_ newVoice: NarrationVoice) {
    voice = newVoice
    VoiceCatalog.savePreference(newVoice)
    restartIfPlaying()
  }

  /// Speak a short greeting in a candidate voice. Pauses any active book
  /// narration first so the sample and the book don't talk over each other.
  func preview(_ candidate: NarrationVoice) {
    if isPlaying { pause() }
    previewSynth.stopSpeaking(at: .immediate)
    let u = AVSpeechUtterance(
      string: "Hi, I'm \(candidate.displayName). I'll be your narrator.")
    u.voice = candidate.avVoice
    u.rate = AVSpeechUtteranceDefaultSpeechRate
    configureSession()
    previewSynth.speak(u)
  }

  // MARK: Controls

  func play() {
    guard !fullText.isEmpty else { return }
    configureSession()
    if synthesizer.isPaused {
      synthesizer.continueSpeaking()
    } else if !synthesizer.isSpeaking {
      speakFromCurrentOffset()
    }
    isPlaying = true
    startTick()
  }

  func pause() {
    restartTask?.cancel()
    restartTask = nil
    if synthesizer.isSpeaking {
      synthesizer.pauseSpeaking(at: .word)
    }
    isPlaying = false
    level = 0
    tickTimer?.invalidate()
    tickTimer = nil
  }

  func toggle() { isPlaying ? pause() : play() }

  func stop() {
    restartTask?.cancel()
    restartTask = nil
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
    spokenWordRange = nil
    level = 0
    tickTimer?.invalidate()
    tickTimer = nil
  }

  func setRate(_ newRate: Float) {
    rate = newRate
    restartIfPlaying()
  }

  func setPitch(_ newPitch: Float) {
    pitch = newPitch
    restartIfPlaying()
  }

  /// Skip forward/back by approximately one sentence worth of characters.
  func skip(_ direction: Int) {
    let ns = fullText as NSString
    let approx = 220 * direction
    let newOffset = min(max(0, charOffset + approx), ns.length)
    charOffset = snapToWordBoundary(newOffset)
    spokenWordRange = nil
    restartImmediatelyIfPlaying()
  }

  func seek(toOffset offset: Int) {
    let ns = fullText as NSString
    charOffset = snapToWordBoundary(min(max(0, offset), ns.length))
    spokenWordRange = nil
    restartImmediatelyIfPlaying()
  }

  // MARK: Sleep timer

  func setSleepTimer(minutes: Int?) {
    sleepTimerMinutes = minutes
    if let minutes {
      sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
    } else {
      sleepDeadline = nil
    }
  }

  /// Seconds remaining on the sleep timer, or nil if off.
  var sleepSecondsRemaining: Int? {
    guard let sleepDeadline else { return nil }
    return max(0, Int(sleepDeadline.timeIntervalSinceNow))
  }

  // MARK: Internal

  private func restartIfPlaying() {
    guard isPlaying else { return }
    // Sliders call this repeatedly. Debouncing avoids stopping/requeuing speech
    // dozens of times per second while the user drags a control.
    restartTask?.cancel()
    restartTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled, let self, self.isPlaying else { return }
      self.synthesizer.stopSpeaking(at: .immediate)
      self.speakFromCurrentOffset()
    }
  }

  private func restartImmediatelyIfPlaying() {
    guard isPlaying else { return }
    restartTask?.cancel()
    restartTask = nil
    synthesizer.stopSpeaking(at: .immediate)
    speakFromCurrentOffset()
  }

  private func speakFromCurrentOffset() {
    let ns = fullText as NSString
    guard charOffset < ns.length else {
      isPlaying = false
      tickTimer?.invalidate()
      tickTimer = nil
      return
    }
    utteranceStart = charOffset
    utteranceEnd = nextUtteranceEnd(in: ns, from: utteranceStart)
    guard utteranceEnd > utteranceStart else {
      isPlaying = false
      return
    }
    let utterance = AVSpeechUtterance(
      string: ns.substring(with: NSRange(location: utteranceStart, length: utteranceEnd - utteranceStart)))
    utterance.voice = voice?.avVoice
    utterance.rate = rate
    utterance.pitchMultiplier = pitch
    utterance.postUtteranceDelay = 0
    synthesizer.speak(utterance)
  }

  /// Chooses a stable break close to the requested chunk size, preferring a
  /// paragraph or sentence ending and falling back to whitespace. Offsets are
  /// UTF-16 to match AVSpeechSynthesizer's delegate ranges.
  private func nextUtteranceEnd(in text: NSString, from start: Int) -> Int {
    let proposed = min(text.length, start + maximumUtteranceLength)
    guard proposed < text.length else { return text.length }
    let searchStart = max(start, proposed - 1_500)
    var whitespaceFallback: Int?
    var index = proposed
    while index > searchStart {
      let codeUnit = text.character(at: index - 1)
      if codeUnit == 0x0A { return index }
      if codeUnit == 0x2E || codeUnit == 0x21 || codeUnit == 0x3F {
        return index
      }
      if whitespaceFallback == nil,
        let scalar = Unicode.Scalar(codeUnit),
        CharacterSet.whitespacesAndNewlines.contains(scalar)
      {
        whitespaceFallback = index
      }
      index -= 1
    }
    return whitespaceFallback ?? proposed
  }

  private func startTick() {
    tickTimer?.invalidate()
    tickTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      guard let self else { return }
      // Synthesize a gentle pseudo-amplitude for the waveform while speaking.
      self.level = self.isPlaying ? Double.random(in: 0.25...1.0) : 0
      if let remaining = self.sleepSecondsRemaining, remaining <= 0 {
        self.pause()
        self.setSleepTimer(minutes: nil)
      }
    }
  }

  private func snapToWordBoundary(_ offset: Int) -> Int {
    let ns = fullText as NSString
    guard offset > 0, offset < ns.length else { return offset }
    var i = offset
    while i > 0 {
      let c = ns.character(at: i - 1)
      if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
        break
      }
      i -= 1
    }
    return i
  }

  private func configureSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true)
  }

  // MARK: AVSpeechSynthesizerDelegate

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
  ) {
    let global = NSRange(
      location: utteranceStart + characterRange.location, length: characterRange.length)
    DispatchQueue.main.async {
      self.spokenWordRange = global
      self.charOffset = global.location
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    DispatchQueue.main.async {
      guard self.isPlaying else { return }
      self.charOffset = self.utteranceEnd
      self.spokenWordRange = nil
      if self.charOffset < (self.fullText as NSString).length {
        self.speakFromCurrentOffset()
      } else {
        self.isPlaying = false
        self.level = 0
        self.tickTimer?.invalidate()
        self.tickTimer = nil
      }
    }
  }
}

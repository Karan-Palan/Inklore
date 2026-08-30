import AVFoundation
import Foundation
import SwiftUI

/// A single reader-facing narration engine with an on-device default and an
/// optional, server-routed ElevenLabs voice. Cloud narration is deliberately
/// bounded to a short chunk and falls back to the selected system voice if the
/// service cannot provide playable audio.
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
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
  // A 4,500-character server request routinely takes long enough that it feels
  // broken in a player. Keep cloud requests to about a short paragraph: this
  // gets the first audio on screen quickly, bounds the JSON/base64 payload, and
  // gives us natural points to prefetch the next bit while this one plays.
  private let maximumCloudUtteranceLength = 1_100
  private let cloudCacheLimit = 6

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
  /// An optional cloud voice selected from Inkflow's backend catalogue.
  var elevenLabsVoice: ElevenLabsVoice?
  /// A non-blocking status used by the picker/player if cloud audio falls back.
  var cloudStatusMessage: String?

  private var cloudPlayer: AVAudioPlayer?
  private var cloudRequestTask: Task<Void, Never>?
  private var cloudChunkStart = 0
  private var cloudChunkEnd = 0
  private var cloudChunkText = ""
  private var cloudAlignment: CloudNarrationAlignment?
  private var cloudFallbackActive = false
  private var cloudPrefetchTask: Task<Void, Never>?
  private var cloudPrefetchKey: CloudChunkKey?
  private var cloudRequestKey: CloudChunkKey?
  private var cloudRequestGeneration = 0
  private var cloudCache: [CloudChunkKey: CachedCloudChunk] = [:]
  private var cloudCacheOrder: [CloudChunkKey] = []

  private struct CloudChunkKey: Hashable {
    let voiceID: String
    let start: Int
    let end: Int
  }

  private struct CachedCloudChunk {
    let audio: Data
    let alignment: CloudNarrationAlignment?
    let text: String
  }

  // Sleep timer.
  var sleepTimerMinutes: Int?  // nil = off
  private var sleepDeadline: Date?
  private var tickTimer: Timer?

  /// Retained synthesizer for voice previews. A local synthesizer would be
  /// deallocated as soon as `preview(_:)` returns, silencing the sample.
  private let previewSynth = AVSpeechSynthesizer()
  private var previewPlayer: AVPlayer?

  override init() {
    super.init()
    synthesizer.delegate = self
    voice = VoiceCatalog.preferred()
    elevenLabsVoice = VoiceCatalog.preferredElevenLabsVoice()
  }

  /// Configure the narrator with text and a starting offset.
  func load(text: String, startOffset: Int) {
    stop()
    fullText = text
    charOffset = min(max(0, startOffset), (text as NSString).length)
    utteranceStart = charOffset
    utteranceEnd = charOffset
    cloudFallbackActive = false
    cloudCache.removeAll(keepingCapacity: true)
    cloudCacheOrder.removeAll(keepingCapacity: true)
  }

  var voiceName: String {
    if isUsingElevenLabsVoice { return elevenLabsVoice?.name ?? "ElevenLabs" }
    return voice?.displayName ?? "System voice"
  }

  var isUsingElevenLabsVoice: Bool { elevenLabsVoice != nil && !cloudFallbackActive }

  /// Selects a new voice, persists it, and restarts speech mid-stream if playing.
  func selectVoice(_ newVoice: NarrationVoice) {
    voice = newVoice
    elevenLabsVoice = nil
    cloudFallbackActive = false
    cloudStatusMessage = nil
    invalidateCloudWork(cancelPrefetch: true)
    VoiceCatalog.savePreference(newVoice)
    restartIfPlaying()
  }

  /// Select an approved provider voice. The current system voice remains in
  /// memory as the automatic offline/service-error fallback.
  func selectVoice(_ newVoice: ElevenLabsVoice) {
    invalidateCloudWork(cancelPrefetch: true)
    elevenLabsVoice = newVoice
    cloudFallbackActive = false
    cloudStatusMessage = nil
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

  /// Play the provider's short public preview directly; narration itself always
  /// remains routed through Inkflow's backend.
  func preview(_ candidate: ElevenLabsVoice) {
    if isPlaying { pause() }
    previewSynth.stopSpeaking(at: .immediate)
    previewPlayer?.pause()
    guard let url = candidate.previewURL else {
      cloudStatusMessage = "A preview is not available for this voice."
      return
    }
    configureSession()
    let player = AVPlayer(url: url)
    previewPlayer = player
    player.play()
  }

  // MARK: Controls

  func play() {
    guard !fullText.isEmpty else { return }
    configureSession()
    if isUsingElevenLabsVoice {
      playCloudNarration()
      return
    }
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
    if isUsingElevenLabsVoice {
      // Do not cancel a request already in flight. Its result is retained and
      // resumes instantly when the listener comes back, instead of triggering
      // another provider request (and another wait/billable generation).
      cloudPlayer?.pause()
      if cloudRequestTask != nil { cloudStatusMessage = "ElevenLabs narration is readying — tap play to resume." }
    } else if synthesizer.isSpeaking {
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
    invalidateCloudWork(cancelPrefetch: true)
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
    cloudPlayer?.stop()
    cloudPlayer = nil
    cloudAlignment = nil
    cloudChunkText = ""
    cloudStatusMessage = nil
    previewPlayer?.pause()
    spokenWordRange = nil
    level = 0
    tickTimer?.invalidate()
    tickTimer = nil
  }

  func setRate(_ newRate: Float) {
    rate = newRate
    if isUsingElevenLabsVoice {
      // Rate is a local AVAudioPlayer setting. Changing it while a cloud
      // chunk is downloading must never throw away that request.
      cloudPlayer?.enableRate = true
      cloudPlayer?.rate = playbackRate
      return
    }
    restartIfPlaying()
  }

  func setPitch(_ newPitch: Float) {
    pitch = newPitch
    // The cloud route deliberately uses the provider's approved settings; pitch
    // remains a system-speech control and should not trigger billed regeneration.
    if isUsingElevenLabsVoice { return }
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
    if isUsingElevenLabsVoice {
      restartCloudNarration()
      return
    }
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
    if isUsingElevenLabsVoice {
      restartCloudNarration()
      return
    }
    synthesizer.stopSpeaking(at: .immediate)
    speakFromCurrentOffset()
  }

  // MARK: Cloud narration

  private var playbackRate: Float {
    max(0.5, min(2.0, rate / AVSpeechUtteranceDefaultSpeechRate))
  }

  private func playCloudNarration() {
    guard let elevenLabsVoice else {
      speakFromCurrentOffset()
      return
    }
    if let cloudPlayer, cloudChunkStart <= charOffset, charOffset < cloudChunkEnd {
      cloudPlayer.enableRate = true
      cloudPlayer.rate = playbackRate
      if !cloudPlayer.isPlaying { cloudPlayer.play() }
      isPlaying = true
      startTick()
      return
    }
    // A paused request intentionally remains alive. It will either already be
    // cached or finish into a paused AVAudioPlayer, so this tap must not start
    // a duplicate provider request.
    if cloudRequestKey?.voiceID == elevenLabsVoice.id,
      cloudRequestKey?.start == charOffset
    {
      isPlaying = true
      cloudStatusMessage = "Preparing ElevenLabs narration…"
      startTick()
      return
    }
    requestCloudNarration(voiceID: elevenLabsVoice.id)
  }

  private func restartCloudNarration() {
    invalidateCloudWork(cancelPrefetch: true)
    synthesizer.stopSpeaking(at: .immediate)
    guard let elevenLabsVoice else {
      speakFromCurrentOffset()
      return
    }
    requestCloudNarration(voiceID: elevenLabsVoice.id)
  }

  private func requestCloudNarration(voiceID: String) {
    let source = fullText as NSString
    guard charOffset < source.length else {
      finishNarration()
      return
    }

    let start = charOffset
    let end = nextCloudUtteranceEnd(in: source, from: start)
    guard end > start else {
      finishNarration()
      return
    }
    let chunk = source.substring(with: NSRange(location: start, length: end - start))
    let key = CloudChunkKey(voiceID: voiceID, start: start, end: end)

    synthesizer.stopSpeaking(at: .immediate)
    cloudPlayer?.stop()
    cloudPlayer = nil
    cloudAlignment = nil
    cloudRequestTask?.cancel()
    cloudRequestTask = nil

    isPlaying = true
    if let cached = cachedCloudChunk(for: key) {
      beginCloudPlayback(cached, key: key, shouldPlay: true)
      return
    }

    if cloudPrefetchKey == key, cloudPrefetchTask != nil {
      // The next paragraph is already being produced. Mark it as foreground
      // work and let the prefetch completion promote its result; do not submit
      // an identical second ElevenLabs request.
      cloudRequestKey = key
      cloudStatusMessage = "Preparing ElevenLabs narration…"
      startTick()
      return
    }

    let generation = cloudRequestGeneration
    cloudRequestKey = key
    cloudStatusMessage = "Preparing ElevenLabs narration…"
    startTick()

    cloudRequestTask = Task { [weak self] in
      do {
        let result = try await CloudNarrationService.narrate(text: chunk, voiceID: voiceID)
        guard !Task.isCancelled else { return }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.cloudRequestGeneration == generation,
            self.cloudRequestKey == key, self.isUsingElevenLabsVoice,
            self.elevenLabsVoice?.id == voiceID, self.charOffset == start
          else { return }
          guard let audio = Data(base64Encoded: result.audioBase64) else {
            self.fallBackToSystemSpeech(after: VoiceServiceError.unsupportedProvider)
            return
          }
          let cached = CachedCloudChunk(
            audio: audio, alignment: result.alignment ?? result.normalizedAlignment, text: chunk)
          self.cacheCloudChunk(cached, for: key)
          self.beginCloudPlayback(cached, key: key, shouldPlay: self.isPlaying)
        }
      } catch {
        guard !Task.isCancelled else { return }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.cloudRequestGeneration == generation,
            self.cloudRequestKey == key
          else { return }
          self.fallBackToSystemSpeech(after: error)
        }
      }
    }
  }

  private func beginCloudPlayback(
    _ cached: CachedCloudChunk, key: CloudChunkKey, shouldPlay: Bool
  ) {
    do {
      let player = try AVAudioPlayer(data: cached.audio)
      player.delegate = self
      player.enableRate = true
      player.rate = playbackRate
      player.prepareToPlay()
      cloudChunkStart = key.start
      cloudChunkEnd = key.end
      cloudChunkText = cached.text
      // Original alignment maps to the submitted text; use it first so reader
      // highlighting remains in the same UTF-16 space as the book.
      cloudAlignment = cached.alignment
      cloudPlayer = player
      cloudRequestTask = nil
      cloudRequestKey = nil
      cloudStatusMessage = shouldPlay ? nil : "ElevenLabs narration is ready to resume."
      if shouldPlay {
        player.play()
        prefetchCloudNarration(after: key, voiceID: key.voiceID)
      }
    } catch {
      fallBackToSystemSpeech(after: error)
    }
  }

  /// Cancels stale work by generation rather than trusting URLSession
  /// cancellation alone: a response can still arrive after a rapid seek or a
  /// voice switch. Cached chunks are intentionally retained for quick seeks.
  private func invalidateCloudWork(cancelPrefetch: Bool) {
    cloudRequestGeneration &+= 1
    cloudRequestTask?.cancel()
    cloudRequestTask = nil
    cloudRequestKey = nil
    if cancelPrefetch {
      cloudPrefetchTask?.cancel()
      cloudPrefetchTask = nil
      cloudPrefetchKey = nil
    }
    cloudPlayer?.stop()
    cloudPlayer = nil
    cloudAlignment = nil
  }

  private func cachedCloudChunk(for key: CloudChunkKey) -> CachedCloudChunk? {
    guard let chunk = cloudCache[key] else { return nil }
    cloudCacheOrder.removeAll { $0 == key }
    cloudCacheOrder.append(key)
    return chunk
  }

  private func cacheCloudChunk(_ chunk: CachedCloudChunk, for key: CloudChunkKey) {
    cloudCache[key] = chunk
    cloudCacheOrder.removeAll { $0 == key }
    cloudCacheOrder.append(key)
    while cloudCacheOrder.count > cloudCacheLimit {
      cloudCache.removeValue(forKey: cloudCacheOrder.removeFirst())
    }
  }

  /// Keep exactly one upcoming chunk warm. This removes the chapter-boundary
  /// silence without queueing an entire book or retaining unbounded audio.
  private func prefetchCloudNarration(after key: CloudChunkKey, voiceID: String) {
    let source = fullText as NSString
    guard key.end < source.length, cloudPrefetchTask == nil else { return }
    let end = nextCloudUtteranceEnd(in: source, from: key.end)
    guard end > key.end else { return }
    let nextKey = CloudChunkKey(voiceID: voiceID, start: key.end, end: end)
    guard cloudCache[nextKey] == nil else { return }
    let text = source.substring(with: NSRange(location: key.end, length: end - key.end))
    let generation = cloudRequestGeneration
    cloudPrefetchKey = nextKey
    cloudPrefetchTask = Task { [weak self] in
      defer {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.cloudPrefetchKey == nextKey else { return }
          self.cloudPrefetchTask = nil
          self.cloudPrefetchKey = nil
        }
      }
      do {
        let result = try await CloudNarrationService.narrate(text: text, voiceID: voiceID)
        guard !Task.isCancelled, let audio = Data(base64Encoded: result.audioBase64) else { return }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.cloudRequestGeneration == generation,
            self.elevenLabsVoice?.id == voiceID
          else { return }
          let cached = CachedCloudChunk(
            audio: audio, alignment: result.alignment ?? result.normalizedAlignment, text: text)
          self.cacheCloudChunk(cached, for: nextKey)
          // The listener reached the prefetch boundary before it completed.
          // Promote the result directly instead of sending the same paragraph
          // to the provider a second time.
          if self.cloudRequestKey == nextKey {
            self.beginCloudPlayback(cached, key: nextKey, shouldPlay: self.isPlaying)
          }
        }
      } catch {
        // Prefetch is an optimisation. The foreground request preserves the
        // existing system-voice fallback and is the only path that reports an
        // error to the reader. If it became foreground work in the meantime,
        // preserve the same visible fallback behavior as a normal request.
        DispatchQueue.main.async { [weak self] in
          guard let self, self.cloudRequestGeneration == generation,
            self.cloudRequestKey == nextKey
          else { return }
          self.fallBackToSystemSpeech(after: error)
        }
      }
    }
  }

  private func fallBackToSystemSpeech(after _: Error) {
    guard isPlaying else { return }
    cloudRequestTask = nil
    cloudRequestKey = nil
    cloudPlayer?.stop()
    cloudPlayer = nil
    cloudAlignment = nil
    cloudFallbackActive = true
    cloudStatusMessage = "ElevenLabs is unavailable. Continuing with your system voice."
    speakFromCurrentOffset()
  }

  private func finishNarration() {
    isPlaying = false
    level = 0
    spokenWordRange = nil
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func nextCloudUtteranceEnd(in text: NSString, from start: Int) -> Int {
    let proposed = min(text.length, start + maximumCloudUtteranceLength)
    guard proposed < text.length else { return text.length }
    let searchStart = max(start, proposed - 900)
    var whitespaceFallback: Int?
    var index = proposed
    while index > searchStart {
      let codeUnit = text.character(at: index - 1)
      if codeUnit == 0x0A || codeUnit == 0x2E || codeUnit == 0x21 || codeUnit == 0x3F {
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

  private func updateCloudProgress() {
    guard let cloudPlayer, cloudPlayer.isPlaying,
      let alignment = cloudAlignment,
      !alignment.characters.isEmpty,
      !alignment.characterEndTimes.isEmpty
    else { return }

    let timingIndex = alignment.characterEndTimes.firstIndex { $0 >= cloudPlayer.currentTime }
      ?? min(alignment.characters.count - 1, alignment.characterEndTimes.count - 1)
    let safeIndex = min(timingIndex, alignment.characters.count - 1)
    let utf16Offset = alignment.characters.prefix(safeIndex).reduce(into: 0) { total, character in
      total += (character as NSString).length
    }
    let text = cloudChunkText as NSString
    guard text.length > 0 else { return }
    let localOffset = min(max(0, utf16Offset), text.length - 1)
    let globalOffset = cloudChunkStart + localOffset
    charOffset = globalOffset
    spokenWordRange = wordRange(in: text, containing: localOffset, globalStart: cloudChunkStart)
  }

  private func wordRange(in text: NSString, containing offset: Int, globalStart: Int) -> NSRange {
    var start = offset
    var end = offset
    while start > 0, !isWhitespace(text.character(at: start - 1)) { start -= 1 }
    while end < text.length, !isWhitespace(text.character(at: end)) { end += 1 }
    if end == start { end = min(text.length, start + 1) }
    return NSRange(location: globalStart + start, length: max(1, end - start))
  }

  private func isWhitespace(_ codeUnit: unichar) -> Bool {
    guard let scalar = Unicode.Scalar(codeUnit) else { return false }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
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
    // Five lightweight updates per second are visually smooth, but avoid the
    // needless SwiftUI/model churn of ticking at every audio-frame boundary.
    tickTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
      guard let self else { return }
      // Synthesize a gentle pseudo-amplitude for the waveform while speaking.
      self.level = self.isPlaying ? Double.random(in: 0.25...1.0) : 0
      if self.isUsingElevenLabsVoice { self.updateCloudProgress() }
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

  // MARK: AVAudioPlayerDelegate

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    DispatchQueue.main.async {
      guard self.cloudPlayer === player, self.isPlaying else { return }
      guard flag else {
        self.fallBackToSystemSpeech(after: VoiceServiceError.unsupportedProvider)
        return
      }
      self.charOffset = self.cloudChunkEnd
      self.spokenWordRange = nil
      self.cloudPlayer = nil
      self.cloudAlignment = nil
      guard self.charOffset < (self.fullText as NSString).length,
        let voiceID = self.elevenLabsVoice?.id,
        self.isUsingElevenLabsVoice
      else {
        self.finishNarration()
        return
      }
      // This first consults the bounded memory cache populated while the
      // preceding paragraph played; it only calls ElevenLabs when necessary.
      self.requestCloudNarration(voiceID: voiceID)
    }
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

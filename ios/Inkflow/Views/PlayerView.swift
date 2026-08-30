import AVFoundation
import SwiftData
import SwiftUI

/// Cover-forward audiobook player that narrates the book's real text with
/// on-device text-to-speech. Goes beyond a basic audio screen: a live waveform,
/// a full cast of selectable narrator voices, sleep timer, fine speed + pitch
/// control, and a one-tap switch to reading. Progress stays synced with reading.
struct PlayerView: View {
  @Bindable var book: Book
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var narrator = SpeechReader()
  @State private var presentReader = false
  @State private var showVoicePicker = false
  @State private var showSpeedSheet = false
  @State private var showChapterSummary = false
  @State private var scrubValue: Double = 0
  @State private var scrubbing = false
  @State private var openedAt = Date()

  private let sleepOptions = [5, 10, 15, 30, 45, 60]
  private let speedMultiples: [Float] = [0.8, 1.0, 1.2, 1.5, 2.0]

  /// After loading, use the narrator's retained text instead of rebuilding a
  /// sample book's `bodyText` on every waveform/word update.
  private var bodyLength: Double { Double(max((narrator.fullText as NSString).length, 1)) }

  var body: some View {
    ZStack {
      backdrop
      GeometryReader { proxy in
        ScrollView(showsIndicators: false) {
          VStack(spacing: playerSpacing) {
            Spacer(minLength: 4)
            Text("AUDIOBOOK")
              .font(.caption2.weight(.bold))
              .tracking(1.6)
              .foregroundStyle(.white.opacity(0.58))

            BookCover(book: book, width: coverWidth(for: proxy.size), showAudioBadge: false)
              .scaleEffect(narrator.isPlaying ? 1 : 0.965)
              .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
              .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: narrator.isPlaying)

            VStack(spacing: 5) {
              Text(book.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
              Text(book.author)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, Theme.xl)

            listeningPosition
            if let cloudStatus = narrator.cloudStatusMessage {
              cloudStatusNotice(cloudStatus)
            }
            waveformCard
            scrubber
            transport
            bottomControls
            Spacer(minLength: 4)
          }
          .frame(maxWidth: 560)
          .frame(minHeight: proxy.size.height, alignment: .center)
          .padding(.horizontal, Theme.lg)
          .padding(.vertical, Theme.md)
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) { topBar }
    .onAppear {
      book.restoreCanonicalCharacterOffset()
      let startOffset = narrationStartOffset
      narrator.load(text: book.bodyText, startOffset: startOffset)
      scrubValue = Double(startOffset)
    }
    .onChange(of: narrator.charOffset) { _, new in
      if !scrubbing { scrubValue = Double(new) }
      // Keep the book's reading position synced live while listening, so the
      // completion percentage matches whether the user reads or listens.
      let narrationLength = (narrator.fullText as NSString).length
      // AVSpeechSynthesizer emits a callback per word. Updating a SwiftData
      // model for every callback causes needless view invalidations and disk
      // autosave pressure, so checkpoint periodically and at completion.
      if abs(book.charOffset - new) >= 500 || new >= narrationLength - 1 {
        // The active audio head is an explicit seekable source, so a user can
        // intentionally scrub backwards. Covered reader views use monotonic
        // writes and cannot undo this newer position on disappearance.
        book.updateCharacterOffset(new, allowingBackward: true)
        syncNativePosition(from: new)
      }
      if new >= narrationLength - 1, narrationLength > 0 {
        book.isFinished = true
      }
    }
    .onDisappear { commitAndStop() }
    .fullScreenCover(isPresented: $presentReader) {
      BookReader(book: book)
    }
    .sheet(isPresented: $showVoicePicker) {
      VoicePickerSheet(narrator: narrator)
    }
    .sheet(isPresented: $showSpeedSheet) {
      speedSheet
        .presentationDetents([.medium])
    }
    .sheet(isPresented: $showChapterSummary) {
      ChapterSummaryView(book: book, initialOffset: narrator.charOffset)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .__tenxTrackView("PlayerView")
  }

  private var backdrop: some View {
    LinearGradient(
      colors: [Color(hex: book.coverHexStart), Color(hex: book.coverHexEnd), .black],
      startPoint: .top, endPoint: .bottom
    )
    .ignoresSafeArea()
    .overlay(Color.black.opacity(0.3).ignoresSafeArea())
  }

  private var playerSpacing: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? Theme.md : Theme.lg
  }

  private func coverWidth(for size: CGSize) -> CGFloat {
    let compactHeight = dynamicTypeSize.isAccessibilitySize ? 0.19 : 0.245
    return min(202, max(136, size.height * compactHeight))
  }

  private var topBar: some View {
    HStack {
      Button {
        commitAndStop()
        dismiss()
      } label: {
        Image(systemName: "chevron.down")
          .frame(width: 38, height: 38)
          .background(.white.opacity(0.12), in: Circle())
      }
      .accessibilityLabel("Dismiss player")
      Spacer()
      Text("Now listening").font(.subheadline.weight(.semibold))
      Spacer()
      sleepMenu
    }
    .font(.title3.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, Theme.xl)
    .padding(.top, Theme.xs)
  }

  private var sleepMenu: some View {
    Menu {
      Button {
        narrator.setSleepTimer(minutes: nil)
      } label: {
        Label("Off", systemImage: narrator.sleepTimerMinutes == nil ? "checkmark" : "moon")
      }
      ForEach(sleepOptions, id: \.self) { m in
        Button {
          narrator.setSleepTimer(minutes: m)
        } label: {
          Label(
            "\(m) minutes",
            systemImage: narrator.sleepTimerMinutes == m ? "checkmark" : "moon.zzz")
        }
      }
    } label: {
      Image(systemName: narrator.sleepTimerMinutes == nil ? "moon" : "moon.zzz.fill")
        .frame(width: 38, height: 38)
        .background(.white.opacity(0.12), in: Circle())
    }
    .accessibilityLabel(
      narrator.sleepTimerMinutes == nil ? "Set sleep timer" : "Sleep timer is active")
  }

  /// A compact bridge between the current text position and the audio head.
  private var listeningPosition: some View {
    HStack(spacing: Theme.md) {
      Image(systemName: "text.book.closed.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Theme.accent, in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(narrator.isUsingElevenLabsVoice ? "ELEVENLABS · LISTENING IN" : "LISTENING IN")
          .font(.caption2.weight(.bold))
          .tracking(0.8)
          .foregroundStyle(.white.opacity(0.56))
        Text(currentChapterTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
      }
      Spacer(minLength: Theme.sm)
      Text("\(Int(playbackProgress * 100))%")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(.white.opacity(0.78))
    }
    .padding(.horizontal, Theme.md)
    .padding(.vertical, Theme.sm)
    .background(
      .white.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Listening in \(currentChapterTitle), \(Int(playbackProgress * 100)) percent complete")
  }

  private func cloudStatusNotice(_ message: String) -> some View {
    Label(message, systemImage: "info.circle.fill")
      .font(.caption)
      .foregroundStyle(.white.opacity(0.84))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Theme.md)
      .padding(.vertical, Theme.sm)
      .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.radiusSm))
      .accessibilityLabel(message)
  }

  private var waveformCard: some View {
    VStack(spacing: Theme.xs) {
      AudioWaveform(level: narrator.level, isPlaying: narrator.isPlaying)
      narratedLine
    }
    .padding(.vertical, Theme.sm)
    .padding(.horizontal, Theme.md)
    .background(
      .black.opacity(0.13), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
  }

  /// The sentence currently being narrated.
  private var narratedLine: some View {
    Text(currentSnippet)
      .font(.caption)
      .italic()
      .multilineTextAlignment(.center)
      .foregroundStyle(.white.opacity(0.85))
      .lineLimit(2)
      .frame(minHeight: 30)
      .animation(reduceMotion ? nil : .default, value: currentSnippet)
      .accessibilityLabel("Current narration: \(currentSnippet)")
  }

  private var scrubber: some View {
    VStack(spacing: 4) {
      Slider(value: $scrubValue, in: 0...bodyLength) { editing in
        scrubbing = editing
        if !editing { narrator.seek(toOffset: Int(scrubValue)) }
      }
      .tint(.white)
      .accessibilityLabel("Reading position")
      .accessibilityValue("\(Int(playbackProgress * 100)) percent")
      HStack {
        Text("\(Int(playbackProgress * 100))% played")
        Spacer()
        if let remaining = narrator.sleepSecondsRemaining {
          Label(sleepClock(remaining), systemImage: "moon.zzz.fill")
            .foregroundStyle(.white.opacity(0.9))
        }
        Spacer()
        Text("\(Int(max(0, 1 - playbackProgress) * 100))% left")
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.white.opacity(0.7))
    }
    .padding(.horizontal, Theme.xl)
  }

  private var transport: some View {
    HStack(spacing: Theme.xxl) {
      Button {
        narrator.skip(-1)
      } label: {
        Image(systemName: "gobackward.15")
      }
      .accessibilityLabel("Back 15 seconds")
      Button {
        narrator.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      } label: {
        Image(systemName: narrator.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 76))
      }
      .accessibilityLabel(narrator.isPlaying ? "Pause" : "Play")
      Button {
        narrator.skip(1)
      } label: {
        Image(systemName: "goforward.15")
      }
      .accessibilityLabel("Forward 15 seconds")
    }
    .font(.system(size: 32, weight: .semibold))
    .foregroundStyle(.white)
    .padding(.top, Theme.sm)
  }

  private var bottomControls: some View {
    VStack(spacing: Theme.sm) {
      HStack(spacing: 0) {
        compactControl(icon: "person.wave.2.fill", title: "Voice", value: narrator.voiceName) {
          showVoicePicker = true
        }
        Divider()
          .overlay(.white.opacity(0.2))
          .padding(.vertical, Theme.sm)
        compactControl(icon: "speedometer", title: "Speed", value: "\(speedLabel(narrator.rate))×") {
          showSpeedSheet = true
        }
        Divider()
          .overlay(.white.opacity(0.2))
          .padding(.vertical, Theme.sm)
        compactControl(icon: "sparkles", title: "Notes", value: "Chapter") {
          showChapterSummary = true
        }
      }
      .background(
        .white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))

      Button {
        narrator.pause()
        commitProgress()
        presentReader = true
      } label: {
        Label("Switch to reading", systemImage: "book.fill")
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, Theme.sm + 2)
          .foregroundStyle(.white)
          .background(Theme.accent, in: Capsule(style: .continuous))
      }
      .accessibilityHint("Keeps this exact listening position")
    }
  }

  private func compactControl(
    icon: String, title: String, value: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .font(.subheadline.weight(.semibold))
        Text(title)
          .font(.caption2.weight(.semibold))
        Text(value)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(1)
      }
      .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Theme.sm)
    .accessibilityLabel("\(title), \(value)")
  }

  // MARK: Speed + pitch sheet

  private var speedSheet: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      Text("Playback")
        .font(.title3.weight(.bold))
        .padding(.top, Theme.lg)

      VStack(alignment: .leading, spacing: Theme.sm) {
        HStack {
          Text("Speed").font(.subheadline.weight(.semibold))
          Spacer()
          Text("\(speedLabel(narrator.rate))×")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.accent)
        }
        HStack(spacing: Theme.sm) {
          ForEach(speedMultiples, id: \.self) { multiple in
            let selected = abs(narrator.rate / AVSpeechUtteranceDefaultSpeechRate - multiple) < 0.06
            Button {
              narrator.setRate(rate(for: multiple))
            } label: {
              Text("\(String(format: "%.1g", multiple))×")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.surfaceAlt, in: Capsule())
            }
            .accessibilityLabel("Set speed to \(String(format: "%.1g", multiple)) times")
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
        Slider(
          value: Binding(
            get: { Double(narrator.rate) },
            set: { narrator.setRate(Float($0)) }),
          in: Double(
            AVSpeechUtteranceMinimumSpeechRate)...Double(
              AVSpeechUtteranceMaximumSpeechRate)
        )
        .tint(Theme.accent)
      }

      VStack(alignment: .leading, spacing: Theme.sm) {
        HStack {
          Text("Pitch").font(.subheadline.weight(.semibold))
          Spacer()
          Text(String(format: "%.1f", narrator.pitch))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.accent)
        }
        Slider(
          value: Binding(
            get: { Double(narrator.pitch) },
            set: { narrator.setPitch(Float($0)) }),
          in: 0.5...2.0
        )
        .tint(Theme.accent)
      }

      Button {
        narrator.setRate(AVSpeechUtteranceDefaultSpeechRate)
        narrator.setPitch(1.0)
      } label: {
        Text("Reset to default")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.accent)
      }

      Spacer()
    }
    .padding(.horizontal, Theme.xl)
    .background(Theme.paper)
  }

  // MARK: Derived + actions

  private var currentSnippet: String {
    let ns = narrator.fullText as NSString
    guard ns.length > 0 else { return "" }
    let start = min(narrator.charOffset, ns.length - 1)
    let length = min(120, ns.length - start)
    return ns.substring(with: NSRange(location: start, length: length))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var currentChapterTitle: String {
    ChapterSummaryContent.section(for: book, offset: narrator.charOffset)?.title
      ?? "Current"
  }

  private var playbackProgress: Double {
    min(1, max(0, scrubValue / bodyLength))
  }

  private func speedLabel(_ rate: Float) -> String {
    let multiple = rate / AVSpeechUtteranceDefaultSpeechRate
    return String(format: "%.2g", multiple)
  }

  private func rate(for multiple: Float) -> Float {
    min(
      AVSpeechUtteranceMaximumSpeechRate,
      max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * multiple))
  }

  private func sleepClock(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func commitProgress() {
    book.updateCharacterOffset(narrator.charOffset, allowingBackward: true)
    syncNativePosition(from: narrator.charOffset)
    book.lastOpenedDate = .now
    let minutes = max(1, Int(Date().timeIntervalSince(openedAt) / 60))
    context.insert(ReadingSession(minutes: minutes, wasListening: true))
    openedAt = Date()
    try? context.save()
  }

  private func commitAndStop() {
    narrator.stop()
    commitProgress()
  }

  /// All modes now resume from Book's shared text anchor. Native EPUB/PDF
  /// locators are mirrored with it by `syncNativePosition`, so a return to the
  /// visual reader cannot use an older page or chapter.
  private var narrationStartOffset: Int {
    min(max(0, book.canonicalCharacterOffset), max(book.bodyNSLength, 0))
  }

  private func syncNativePosition(from offset: Int) {
    let narrationLength = (narrator.fullText as NSString).length
    guard narrationLength > 0 else { return }
    let fraction = min(1, max(0, Double(offset) / Double(narrationLength)))
    if book.isPdf, book.pdfPageCount > 0 {
      let pageIndex = min(
        book.pdfPageCount - 1, max(0, Int(fraction * Double(book.pdfPageCount))))
      book.updatePdfPosition(
        pageIndex: pageIndex,
        pageCount: book.pdfPageCount,
        characterOffset: offset,
        // A player seek is authoritative: it must also be able to replace a
        // legacy/stale native page locator when the user scrubs to zero.
        allowingBackward: true)
    } else if book.isEpub, book.spineCount > 0 {
      let raw = min(
        Double(book.spineCount) - 0.000_001,
        fraction * Double(book.spineCount))
      let index = min(book.spineCount - 1, max(0, Int(raw)))
      book.updateEpubPosition(
        spineIndex: index,
        scroll: raw - Double(index),
        spineCount: book.spineCount,
        characterOffset: offset,
        allowingBackward: true)
    }
  }
}

#Preview {
  PlayerView(book: PreviewData.sampleBook)
    .modelContainer(PreviewData.container)
}

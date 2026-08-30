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

  @State private var narrator = SpeechReader()
  @State private var presentReader = false
  @State private var showVoicePicker = false
  @State private var showSpeedSheet = false
  @State private var showChapterSummary = false
  @State private var scrubValue: Double = 0
  @State private var scrubbing = false
  @State private var openedAt = Date()

  private let sleepOptions = [5, 10, 15, 30, 45, 60]

  /// After loading, use the narrator's retained text instead of rebuilding a
  /// sample book's `bodyText` on every waveform/word update.
  private var bodyLength: Double { Double(max((narrator.fullText as NSString).length, 1)) }

  var body: some View {
    ZStack {
      backdrop
      VStack(spacing: Theme.lg) {
        Spacer(minLength: 0)
        BookCover(book: book, width: 196, showAudioBadge: false)
          .scaleEffect(narrator.isPlaying ? 1 : 0.96)
          .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
          .animation(.smooth(duration: 0.4), value: narrator.isPlaying)

        VStack(spacing: 6) {
          Text(book.title)
            .font(.title2.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
          Text(book.author)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, Theme.xl)

        AudioWaveform(level: narrator.level, isPlaying: narrator.isPlaying)
          .padding(.horizontal, Theme.xl)

        narratedLine
        scrubber
        transport
        bottomControls
        Spacer(minLength: 0)
      }
      .padding(.bottom, Theme.xl)
    }
    .safeAreaInset(edge: .top, spacing: 0) { topBar }
    .onAppear {
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
        book.charOffset = new
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

  private var topBar: some View {
    HStack {
      Button {
        commitAndStop()
        dismiss()
      } label: {
        Image(systemName: "chevron.down")
      }
      Spacer()
      Text("Now Playing").font(.subheadline.weight(.semibold))
      Spacer()
      sleepMenu
    }
    .font(.title3.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, Theme.xl)
    .padding(.top, Theme.sm)
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
    }
  }

  /// The sentence currently being narrated.
  private var narratedLine: some View {
    Text(currentSnippet)
      .font(.callout)
      .italic()
      .multilineTextAlignment(.center)
      .foregroundStyle(.white.opacity(0.85))
      .lineLimit(2)
      .frame(height: 44)
      .padding(.horizontal, Theme.xl)
      .animation(.default, value: currentSnippet)
  }

  private var scrubber: some View {
    VStack(spacing: 4) {
      Slider(value: $scrubValue, in: 0...bodyLength) { editing in
        scrubbing = editing
        if !editing { narrator.seek(toOffset: Int(scrubValue)) }
      }
      .tint(.white)
      HStack {
        Text("\(Int(scrubValue / bodyLength * 100))%")
        Spacer()
        if let remaining = narrator.sleepSecondsRemaining {
          Label(sleepClock(remaining), systemImage: "moon.zzz.fill")
            .foregroundStyle(.white.opacity(0.9))
        }
        Spacer()
        Text("\(Int((bodyLength - scrubValue) / bodyLength * 100))% left")
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
      Button {
        narrator.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      } label: {
        Image(systemName: narrator.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 76))
      }
      Button {
        narrator.skip(1)
      } label: {
        Image(systemName: "goforward.15")
      }
    }
    .font(.system(size: 32, weight: .semibold))
    .foregroundStyle(.white)
    .padding(.top, Theme.sm)
  }

  private var bottomControls: some View {
    HStack(spacing: Theme.sm) {
      playerControl(icon: "person.wave.2.fill", label: "Voice", value: narrator.voiceName) {
        showVoicePicker = true
      }
      playerControl(
        icon: "speedometer", label: "Speed", value: "\(speedLabel(narrator.rate))×"
      ) {
        showSpeedSheet = true
      }
      playerControl(icon: "sparkles", label: "Summary", value: currentChapterTitle) {
        showChapterSummary = true
      }
      Button {
        narrator.pause()
        commitProgress()
        presentReader = true
      } label: {
        VStack(spacing: 6) {
          Image(systemName: "book.fill")
            .font(.title3.weight(.semibold))
            .frame(width: 42, height: 42)
            .background(Theme.accent, in: Circle())
          Text("Read")
            .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.top, Theme.md)
    .padding(.horizontal, Theme.lg)
  }

  private func playerControl(
    icon: String, label: String, value: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: icon)
          .font(.title3.weight(.semibold))
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.14), in: Circle())
        Text(label)
          .font(.caption2.weight(.semibold))
        Text(value)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(1)
      }
      .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity)
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

  private func speedLabel(_ rate: Float) -> String {
    let multiple = rate / AVSpeechUtteranceDefaultSpeechRate
    return String(format: "%.2g", multiple)
  }

  private func sleepClock(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func commitProgress() {
    book.charOffset = narrator.charOffset
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

  /// EPUB and PDF readers store a native chapter/page position rather than a
  /// character offset. Their extracted narration text is still linear, so we
  /// map the native progress to that text on entry and back again while audio
  /// advances. The mapping is approximate for visually laid-out PDFs, but it
  /// keeps a read/listen handoff in the same part of the document.
  private var narrationStartOffset: Int {
    let narrationLength = Double(max(book.bodyNSLength, 1))
    if book.isPdf, book.pdfPageCount > 0 {
      let fraction = Double(book.pdfPageIndex) / Double(book.pdfPageCount)
      return min(Int(narrationLength), max(0, Int(fraction * narrationLength)))
    }
    if book.isEpub, book.spineCount > 0 {
      let fraction =
        (Double(book.spineIndex) + min(max(book.chapterScroll, 0), 1))
        / Double(book.spineCount)
      return min(Int(narrationLength), max(0, Int(fraction * narrationLength)))
    }
    return min(Int(narrationLength), max(0, book.charOffset))
  }

  private func syncNativePosition(from offset: Int) {
    let narrationLength = (narrator.fullText as NSString).length
    guard narrationLength > 0 else { return }
    let fraction = min(1, max(0, Double(offset) / Double(narrationLength)))
    if book.isPdf, book.pdfPageCount > 0 {
      book.pdfPageIndex = min(
        book.pdfPageCount - 1, max(0, Int(fraction * Double(book.pdfPageCount))))
    } else if book.isEpub, book.spineCount > 0 {
      let raw = min(
        Double(book.spineCount) - 0.000_001,
        fraction * Double(book.spineCount))
      book.spineIndex = min(book.spineCount - 1, max(0, Int(raw)))
      book.chapterScroll = raw - Double(book.spineIndex)
    }
  }
}

#Preview {
  PlayerView(book: PreviewData.sampleBook)
    .modelContainer(PreviewData.container)
}

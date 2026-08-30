import SwiftData
import SwiftUI
import WebKit

/// Full-fidelity EPUB reader. Each spine chapter is a real (X)HTML file rendered
/// by `WKWebView` with its original CSS, images, and formatting intact. We inject
/// a small stylesheet for the chosen reader theme/font/margins, restore the last
/// chapter + scroll position, and tap-zones flip between chapters.
struct EpubReaderView: View {
  @Bindable var book: Book
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

  @State private var settings = ReaderSettings()
  @State private var document: EpubDocument?
  @State private var chapterIndex = 0
  @State private var scrollFraction: Double = 0
  @State private var showChrome = true
  @State private var showSettings = false
  @State private var showContents = false
  @State private var presentPlayer = false
  @State private var loadFailed = false
  @State private var openedAt = Date()
  @State private var chromeVisibilityToken = 0

  var body: some View {
    ZStack {
      settings.theme.pageBackground.ignoresSafeArea()

      if let document, document.chapters.indices.contains(chapterIndex) {
        EpubWebView(
          chapterURL: document.chapters[chapterIndex].url,
          baseURL: document.baseURL,
          settings: settings,
          initialScroll: chapterIndex == book.spineIndex ? book.chapterScroll : 0,
          onScroll: { fraction in
            let bounded = min(1, max(0, fraction))
            // WebKit reports every pixel while scrolling; updating SwiftUI for
            // each one is unnecessary because persistence is approximate.
            if abs(scrollFraction - bounded) >= 0.003 {
              let movedBackward = bounded < scrollFraction
              scrollFraction = bounded
              // Keep the shared text anchor fresh enough for a direct switch
              // into the player. `commitProgress` writes the final pixel-level
              // value before any handoff or dismissal.
              if abs(book.chapterScroll - bounded) >= 0.02 {
                book.updateEpubPosition(
                  spineIndex: chapterIndex,
                  scroll: bounded,
                  spineCount: document.chapters.count,
                  allowingBackward: movedBackward)
              }
            }
          },
          onTapZone: handleTap
        )
        .id(chapterIndex)
        .ignoresSafeArea(edges: .bottom)
      } else if loadFailed {
        failureState
      } else {
        ProgressView("Opening book…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if showChrome { chromeOverlay }

      Color.black
        .opacity((1 - settings.brightness) * 0.55)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
    .statusBarHidden(!showChrome)
    .onAppear {
      load()
      scheduleChromeFade()
    }
    .task(id: chromeVisibilityToken) {
      guard showChrome, !voiceOverEnabled else { return }
      try? await Task.sleep(for: .seconds(4.5))
      guard !Task.isCancelled, showChrome, !showSettings, !showContents else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { showChrome = false }
    }
    .onDisappear(perform: commitProgress)
    .sheet(isPresented: $showSettings) {
      ReaderSettingsSheet(settings: settings)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showContents) {
      if let document {
        EpubContentsSheet(
          chapters: document.chapters, current: chapterIndex,
          theme: settings.theme
        ) { index in
          showContents = false
          goToChapter(index)
        }
        .presentationDetents([.medium, .large])
      }
    }
    .fullScreenCover(isPresented: $presentPlayer) {
      PlayerView(book: book)
    }
    .__tenxTrackView("EpubReaderView")
  }

  // MARK: Loading

  private func load() {
    openedAt = Date()
    book.lastOpenedDate = .now
    guard let doc = EpubDocument(folderName: book.epubFolderName) else {
      loadFailed = true
      return
    }
    document = doc
    book.restoreCanonicalCharacterOffset()
    // The shared text offset wins when audio advanced since this reader was
    // last visible. This also migrates legacy native-only EPUB positions.
    let locator = book.epubLocatorForCanonicalPosition(spineCount: doc.chapters.count)
    book.updateEpubPosition(
      spineIndex: locator.index,
      scroll: locator.scroll,
      spineCount: doc.chapters.count,
      characterOffset: book.canonicalCharacterOffset,
      allowingBackward: true)
    chapterIndex = locator.index
    scrollFraction = locator.scroll
  }

  private func handleTap(_ zone: EpubWebView.TapZone) {
    switch zone {
    case .left: turnBack()
    case .right: turnForward()
    case .center: toggleChrome()
    }
  }

  private func turnForward() {
    guard let document else { return }
    if chapterIndex < document.chapters.count - 1 {
      goToChapter(chapterIndex + 1)
    }
  }

  private func turnBack() {
    if chapterIndex > 0 { goToChapter(chapterIndex - 1) }
  }

  private func goToChapter(_ index: Int) {
    guard let document, document.chapters.indices.contains(index) else { return }
    commitProgress()
    chapterIndex = index
    scrollFraction = 0
    // Selecting a chapter is deliberate navigation, including backwards.
    book.updateEpubPosition(
      spineIndex: index,
      scroll: 0,
      spineCount: document.chapters.count,
      allowingBackward: true)
  }

  private func commitProgress() {
    if let document {
      // A reader view underneath the player may disappear later with an old
      // local scroll position. The default monotonic write prevents that stale
      // callback from rolling back a newer listening checkpoint.
      book.updateEpubPosition(
        spineIndex: chapterIndex,
        scroll: scrollFraction,
        spineCount: document.chapters.count)
    }
    logSession()
    try? context.save()
  }

  private func logSession() {
    let minutes = Int(Date().timeIntervalSince(openedAt) / 60)
    guard minutes >= 1 else { return }
    context.insert(ReadingSession(minutes: minutes, pagesRead: 0, wasListening: false))
    openedAt = Date()
  }

  // MARK: Chrome

  private var chromeOverlay: some View {
    VStack {
      HStack(spacing: Theme.sm) {
        ReaderChromeButton(systemImage: "chevron.left", label: "Back to library") {
          commitProgress()
          dismiss()
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(book.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text(document?.chapters[safe: chapterIndex]?.title ?? "Chapter \(chapterIndex + 1)")
            .font(.caption2)
            .foregroundStyle(settings.theme.textColor.opacity(0.58))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        ReaderChromeButton(systemImage: "list.bullet", label: "Table of contents") {
          showContents = true
        }
        if book.canListen {
          ReaderChromeButton(systemImage: "headphones", label: "Open audio player") {
            commitProgress()
            presentPlayer = true
          }
        }
        ReaderChromeButton(systemImage: "textformat.size", label: "Reading settings") {
          showSettings = true
        }
      }
      .foregroundStyle(settings.theme.chromeTint)
      .padding(.horizontal, Theme.lg)
      .padding(.vertical, Theme.sm)
      .background(settings.theme.pageBackground.opacity(0.86))
      .background(.ultraThinMaterial)
      .overlay(alignment: .bottom) {
        Rectangle().fill(settings.theme.textColor.opacity(0.09)).frame(height: 0.5)
      }

      Spacer()

      footer
    }
  }

  private var footer: some View {
    VStack(spacing: Theme.md) {
      ReaderProgressFooter(
        progress: readingProgress,
        title: document?.chapters[safe: chapterIndex]?.title ?? book.title,
        detail: "\(Int(readingProgress * 100))% · Ch. \(chapterIndex + 1) of \(max(book.spineCount, 1))",
        foreground: settings.theme.textColor
      )

      if book.canListen {
        ReaderAudioHandoff(
          title: "Listen from this chapter",
          progress: readingProgress,
          foreground: settings.theme.textColor
        ) {
          commitProgress()
          presentPlayer = true
        }
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.md)
    .background(settings.theme.pageBackground.opacity(0.86))
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle().fill(settings.theme.textColor.opacity(0.09)).frame(height: 0.5)
    }
  }

  private var readingProgress: Double {
    guard let document, !document.chapters.isEmpty else { return book.progress }
    let progress = (Double(chapterIndex) + min(1, max(0, scrollFraction)))
      / Double(document.chapters.count)
    return min(1, max(0, progress))
  }

  private func toggleChrome() {
    if showChrome {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showChrome = false }
    } else {
      withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { showChrome = true }
      scheduleChromeFade()
    }
  }

  private func scheduleChromeFade() {
    chromeVisibilityToken &+= 1
  }

  private var failureState: some View {
    ContentUnavailableView {
      Label("Couldn't open this book", systemImage: "book.closed")
    } description: {
      Text("The EPUB file may be damaged. Try downloading it again.")
    } actions: {
      Button("Close") { dismiss() }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

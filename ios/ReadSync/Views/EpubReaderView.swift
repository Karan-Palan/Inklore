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
            if abs(scrollFraction - bounded) >= 0.003 { scrollFraction = bounded }
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
    .onAppear(perform: load)
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
    if book.spineCount != doc.chapters.count {
      book.spineCount = doc.chapters.count
    }
    chapterIndex = min(max(0, book.spineIndex), doc.chapters.count - 1)
    scrollFraction = book.chapterScroll
  }

  private func handleTap(_ zone: EpubWebView.TapZone) {
    switch zone {
    case .left: turnBack()
    case .right: turnForward()
    case .center: withAnimation(.snappy) { showChrome.toggle() }
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
    book.spineIndex = index
    book.chapterScroll = 0
  }

  private func commitProgress() {
    book.spineIndex = chapterIndex
    book.chapterScroll = scrollFraction
    if let document, chapterIndex == document.chapters.count - 1, scrollFraction > 0.92 {
      book.isFinished = true
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
      HStack(spacing: Theme.lg) {
        Button {
          commitProgress()
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
        }
        Spacer()
        Button {
          showContents = true
        } label: {
          Image(systemName: "list.bullet")
        }
        if book.canListen {
          Button {
            presentPlayer = true
          } label: {
            Image(systemName: "headphones")
          }
        }
        Button {
          showSettings = true
        } label: {
          Image(systemName: "textformat.size")
        }
      }
      .font(.title3.weight(.semibold))
      .foregroundStyle(settings.theme.chromeTint)
      .padding(.horizontal, Theme.lg)
      .padding(.vertical, Theme.md)
      .background(.ultraThinMaterial)

      Spacer()

      footer
    }
  }

  private var footer: some View {
    VStack(spacing: 6) {
      ProgressView(value: book.progress)
        .tint(Theme.accent)
      HStack {
        Text(document?.chapters[safe: chapterIndex]?.title ?? book.title)
          .lineLimit(1)
        Spacer()
        Text("\(Int(book.progress * 100))% · ch \(chapterIndex + 1) of \(max(book.spineCount, 1))")
      }
      .font(.caption)
      .foregroundStyle(settings.theme.textColor.opacity(0.7))
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.xl)
    .background(.ultraThinMaterial)
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

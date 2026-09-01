import PDFKit
import SwiftData
import SwiftUI

/// Full-fidelity PDF reader backed by PDFKit. Renders the imported PDF exactly as
/// authored, restores the last page, tracks page progress, and offers a one-tap
/// switch to the audiobook player (shared progress with reading).
struct PdfReaderView: View {
  @Bindable var book: Book
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

  @State private var pdfDocument: PDFDocument?
  @State private var currentPage = 0
  @State private var pageCount = 0
  @State private var showChrome = true
  @State private var presentPlayer = false
  @State private var loadFailed = false
  @State private var openedAt = Date()
  @State private var chromeVisibilityToken = 0

  var body: some View {
    ZStack {
      Theme.paper.ignoresSafeArea()

      if let pdfDocument {
        PdfKitView(
          document: pdfDocument,
          pageIndex: $currentPage,
          onTapCenter: toggleChrome
        )
        .accessibilityHint("Scroll vertically to read. Pinch to zoom. Tap the middle of the page to show or hide reading controls.")
        .ignoresSafeArea(edges: .bottom)
      } else if loadFailed {
        failureState
      } else {
        ProgressView("Opening PDF…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if showChrome { chromeOverlay }
    }
    .statusBarHidden(!showChrome)
    .onAppear(perform: scheduleChromeFade)
    .task { await load() }
    .task(id: chromeVisibilityToken) {
      guard showChrome, !voiceOverEnabled else { return }
      try? await Task.sleep(for: .seconds(4.5))
      guard !Task.isCancelled, showChrome else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { showChrome = false }
    }
    .onChange(of: currentPage) { oldValue, newValue in
      // A page gesture is explicit navigation, including a deliberate move
      // backwards. A later stale `commitProgress` remains monotonic.
      book.updatePdfPosition(
        pageIndex: newValue,
        pageCount: pageCount,
        allowingBackward: newValue < oldValue)
    }
    .onDisappear(perform: commitProgress)
    .fullScreenCover(isPresented: $presentPlayer) {
      PlayerView(book: book)
    }
    .__tenxTrackView("PdfReaderView")
  }

  // MARK: Loading

  private func load() async {
    openedAt = Date()
    book.lastOpenedDate = .now
    let url = PdfStore.fileURL(named: book.pdfFileName)
    let doc = await Task.detached(priority: .userInitiated) {
      PDFDocument(url: url)
    }.value
    guard !Task.isCancelled, let doc, doc.pageCount > 0 else {
      if !Task.isCancelled { loadFailed = true }
      return
    }
    pdfDocument = doc
    pageCount = doc.pageCount
    book.restoreCanonicalCharacterOffset()
    // The text/audio anchor is authoritative after a player handoff; page
    // index remains the native PDF renderer's resume locator.
    let pageIndex = book.pdfPageIndexForCanonicalPosition(pageCount: doc.pageCount)
    book.updatePdfPosition(
      pageIndex: pageIndex,
      pageCount: doc.pageCount,
      characterOffset: book.canonicalCharacterOffset,
      allowingBackward: true)
    currentPage = pageIndex
  }

  private func commitProgress() {
    // This can be invoked when a covered reader disappears after audio has
    // moved forward. Do not let its older local page overwrite that position.
    book.updatePdfPosition(pageIndex: currentPage, pageCount: pageCount)
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
          Text(book.author)
            .font(.caption2)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author)")
        if book.canListen {
          ReaderChromeButton(systemImage: "headphones", label: "Open audio player") {
            commitProgress()
            presentPlayer = true
          }
        }
      }
      .foregroundStyle(Theme.ink)
      .padding(.horizontal, Theme.lg)
      .padding(.vertical, Theme.sm)
      .background(.ultraThinMaterial)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Theme.ink.opacity(0.09)).frame(height: 0.5)
      }

      Spacer()

      footer
    }
  }

  private var footer: some View {
    VStack(spacing: Theme.md) {
      ReaderProgressFooter(
        progress: readingProgress,
        title: book.title,
        detail: "\(Int(readingProgress * 100))% · Page \(currentPage + 1) of \(max(pageCount, 1))",
        foreground: Theme.ink
      )

      Text("Scroll to read · Pinch to zoom")
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)

      if book.canListen {
        ReaderAudioHandoff(
          title: "Listen from this page",
          progress: readingProgress,
          foreground: Theme.ink
        ) {
          commitProgress()
          presentPlayer = true
        }
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.md)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle().fill(Theme.ink.opacity(0.09)).frame(height: 0.5)
    }
  }

  private var readingProgress: Double {
    guard pageCount > 0 else { return 0 }
    return min(1, max(0, Double(currentPage + 1) / Double(pageCount)))
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
      Label("Couldn't open this PDF", systemImage: "doc.richtext")
    } description: {
      Text("The PDF file may be damaged. Try importing it again.")
    } actions: {
      Button("Close") { dismiss() }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
  }
}

/// UIKit `PDFView` bridge for a real, vertically-continuous document canvas.
///
/// PDFKit emits its current page as the reader crosses a page boundary. That
/// value is deliberately one-way after the initial restore: feeding the bound
/// value back into `go(to:)` while the document is being panned interrupts the
/// PDF view's native vertical scroll gesture and is the source of the former
/// tap/page-turn feeling.
private struct PdfKitView: UIViewRepresentable {
  let document: PDFDocument
  @Binding var pageIndex: Int
  let onTapCenter: () -> Void

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.document = document
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.usePageViewController(false)
    view.displaysPageBreaks = true
    view.pageShadowsEnabled = true
    view.backgroundColor = .clear

    if let page = document.page(at: min(max(0, pageIndex), document.pageCount - 1)) {
      view.go(to: page)
    }

    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.pageChanged),
      name: .PDFViewPageChanged,
      object: view
    )

    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tap.cancelsTouchesInView = false
    view.addGestureRecognizer(tap)

    context.coordinator.pdfView = view
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {
    // The initial locator is applied in `makeUIView`. Do not call `go(to:)`
    // here: SwiftUI re-renders as PDFKit reports each newly visible page, and
    // a reciprocal `go(to:)` cancels an in-progress vertical pan.
    if let currentDocument = view.document, currentDocument === document { return }
    view.document = document
    if let target = document.page(at: min(max(0, pageIndex), document.pageCount - 1)) {
      view.go(to: target)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject {
    let parent: PdfKitView
    weak var pdfView: PDFView?

    init(_ parent: PdfKitView) { self.parent = parent }

    @objc func pageChanged() {
      guard let view = pdfView, let page = view.currentPage,
        let index = view.document?.index(for: page)
      else { return }
      if index != parent.pageIndex { parent.pageIndex = index }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let view = pdfView else { return }
      let x = gesture.location(in: view).x
      let width = view.bounds.width
      if x > width * 0.3, x < width * 0.7 {
        parent.onTapCenter()
      }
    }
  }
}

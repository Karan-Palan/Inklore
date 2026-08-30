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

  @State private var pdfDocument: PDFDocument?
  @State private var currentPage = 0
  @State private var pageCount = 0
  @State private var showChrome = true
  @State private var presentPlayer = false
  @State private var loadFailed = false
  @State private var openedAt = Date()

  var body: some View {
    ZStack {
      Color(.systemGray6).ignoresSafeArea()

      if let pdfDocument {
        PdfKitView(
          document: pdfDocument,
          pageIndex: $currentPage,
          onTapCenter: { withAnimation(.snappy) { showChrome.toggle() } }
        )
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
    .onAppear(perform: load)
    .onChange(of: currentPage) { _, newValue in
      book.pdfPageIndex = newValue
      if pageCount > 0, newValue >= pageCount - 1 { book.isFinished = true }
    }
    .onDisappear(perform: commitProgress)
    .fullScreenCover(isPresented: $presentPlayer) {
      PlayerView(book: book)
    }
    .__tenxTrackView("PdfReaderView")
  }

  // MARK: Loading

  private func load() {
    openedAt = Date()
    book.lastOpenedDate = .now
    let url = PdfStore.fileURL(named: book.pdfFileName)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
      loadFailed = true
      return
    }
    pdfDocument = doc
    pageCount = doc.pageCount
    if book.pdfPageCount != doc.pageCount { book.pdfPageCount = doc.pageCount }
    currentPage = min(max(0, book.pdfPageIndex), doc.pageCount - 1)
  }

  private func commitProgress() {
    book.pdfPageIndex = currentPage
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
        if book.canListen {
          Button {
            commitProgress()
            presentPlayer = true
          } label: {
            Image(systemName: "headphones")
          }
        }
      }
      .font(.title3.weight(.semibold))
      .foregroundStyle(Theme.ink)
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
        Text(book.title)
          .lineLimit(1)
        Spacer()
        Text("page \(currentPage + 1) of \(max(pageCount, 1))")
      }
      .font(.caption)
      .foregroundStyle(Theme.inkSoft)
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.xl)
    .background(.ultraThinMaterial)
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

/// UIKit `PDFView` bridge. Keeps the bound page index in sync both ways and
/// reports center taps so the reader can toggle its chrome.
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
    guard let current = view.currentPage,
      let currentIndex = document.index(for: current) as Int?
    else { return }
    if currentIndex != pageIndex,
      let target = document.page(at: min(max(0, pageIndex), document.pageCount - 1))
    {
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

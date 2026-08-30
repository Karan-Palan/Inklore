import SwiftData
import SwiftUI

/// A Kindle-style paginated reader. Text is laid out one page at a time (no
/// scrolling). Tapping the right edge turns to the next page, the left edge to
/// the previous, and the center toggles the chrome. Selecting text raises the
/// highlight / note / lookup toolbar.
struct ReaderView: View {
  @Bindable var book: Book
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  @State private var settings = ReaderSettings()
  @State private var paginator: Paginator?
  @State private var pageIndex = 0
  @State private var pageSize: CGSize = .zero

  @State private var showChrome = true
  @State private var showSettings = false
  @State private var showContents = false
  @State private var showChapterSummary = false
  @State private var presentPlayer = false

  // Read-along narration (highlights each word as it's spoken + auto-turns pages).
  @State private var narrator = SpeechReader()
  @State private var readAlong = false
  @State private var listenStartedAt: Date?

  // Selection flow
  @State private var selection: (text: String, range: NSRange)?
  @State private var lookupTerm: IdentifiedString?
  @State private var noteDraft: NoteDraft?
  @State private var activeHighlight: Highlight?

  @State private var openedAt = Date()

  private var pageInsets: EdgeInsets {
    EdgeInsets(top: 70, leading: settings.margins, bottom: 60, trailing: settings.margins)
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        settings.theme.pageBackground.ignoresSafeArea()

        pageLayer(in: geo.size)

        // Tap zones for page turning + chrome toggle.
        tapZones

        if showChrome { chromeOverlay }

        // Brightness dimming overlay (visual in-reader brightness).
        Color.black
          .opacity((1 - settings.brightness) * 0.55)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
      .overlay(alignment: .bottom) { selectionToolbarLayer }
      .onAppear { repaginate(in: geo.size) }
      .onChange(of: geo.size) { _, newSize in repaginate(in: newSize) }
      .onChange(of: settings.fontSize) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.font) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.lineSpacing) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.margins) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.theme) { _, _ in repaginate(in: geo.size) }
    }
    .statusBarHidden(!showChrome)
    .sheet(isPresented: $showSettings) {
      ReaderSettingsSheet(settings: settings)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showContents) {
      ChapterListSheet(book: book) { offset in
        showContents = false
        goToOffset(offset)
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showChapterSummary) {
      ChapterSummaryView(book: book, initialOffset: book.charOffset)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(item: $lookupTerm) { term in
      LookupSheet(term: term.value)
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(item: $noteDraft) { draft in
      NoteComposer(passage: draft.passage, initialText: draft.existingBody) { body in
        saveNote(passage: draft.passage, range: draft.range, body: body, editing: draft.editingNote)
      }
      .presentationDetents([.height(320)])
    }
    .sheet(item: $activeHighlight) { highlight in
      HighlightActionSheet(
        highlight: highlight,
        existingNote: noteFor(highlight),
        onChangeColor: { color in
          highlight.colorName = color.rawValue
          try? context.save()
        },
        onAddOrEditNote: {
          let existing = noteFor(highlight)
          activeHighlight = nil
          noteDraft = NoteDraft(
            passage: highlight.text, range: highlight.range,
            existingBody: existing?.body ?? "", editingNote: existing)
        },
        onCopy: {
          UIPasteboard.general.string = highlight.text
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        },
        onDelete: {
          if let note = noteFor(highlight) { context.delete(note) }
          context.delete(highlight)
          try? context.save()
        }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $presentPlayer) {
      PlayerView(book: book)
    }
    .onChange(of: narrator.spokenWordRange) { _, range in
      guard readAlong, let range, let paginator else { return }
      // Keep reading progress synced to the spoken word and auto-turn pages so
      // the highlighted word stays on screen.
      let target = paginator.pageIndex(for: range.location)
      if target != pageIndex, paginator.pageRanges.indices.contains(target) {
        withAnimation(.easeInOut(duration: 0.2)) { pageIndex = target }
        book.charOffset = paginator.startOffset(of: target)
      } else if abs(book.charOffset - range.location) >= 500 {
        // Speech callbacks arrive for every word. Avoid dirtying the SwiftData
        // book object at that rate while still retaining frequent checkpoints.
        book.charOffset = range.location
      }
    }
    .onDisappear {
      stopReadAlong()
      commitProgress()
    }
    .__tenxTrackView("ReaderView")
  }

  // MARK: Page layer

  @ViewBuilder
  private func pageLayer(in size: CGSize) -> some View {
    if let paginator, paginator.pageRanges.indices.contains(pageIndex) {
      ReaderPageView(
        attributed: paginator.attributed,
        pageRange: paginator.pageRanges[pageIndex],
        highlights: book.highlights.map {
          ($0.range, (HighlightColor(rawValue: $0.colorName) ?? .yellow).uiColor)
        },
        activeWordRange: readAlong ? narrator.spokenWordRange : nil,
        onSelect: { text, range in
          selection = (text, range)
          UISelectionFeedbackGenerator().selectionChanged()
        },
        onTapHighlight: { globalIndex in
          if let hit = book.highlights.first(where: {
            NSLocationInRange(globalIndex, $0.range)
          }) {
            selection = nil
            activeHighlight = hit
            UISelectionFeedbackGenerator().selectionChanged()
          }
        }
      )
      .id(pageIndex)
      .padding(pageInsets)
      .frame(width: size.width, height: size.height)
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var tapZones: some View {
    HStack(spacing: 0) {
      Color.clear.contentShape(Rectangle())
        .onTapGesture { turn(-1) }
        .frame(maxWidth: .infinity)
      Color.clear.contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { showChrome.toggle() } }
        .frame(width: 90)
      Color.clear.contentShape(Rectangle())
        .onTapGesture { turn(1) }
        .frame(maxWidth: .infinity)
    }
    .ignoresSafeArea()
    // Don't swallow touches over the selection toolbar.
    .allowsHitTesting(selection == nil)
  }

  @ViewBuilder
  private var selectionToolbarLayer: some View {
    if let selection {
      SelectionToolbar(
        onHighlight: { color in addHighlight(selection.text, range: selection.range, color: color)
        },
        onNote: { noteDraft = NoteDraft(passage: selection.text, range: selection.range) },
        onLookup: { lookupTerm = IdentifiedString(firstWords(selection.text)) },
        onCopy: {
          UIPasteboard.general.string = selection.text
          self.selection = nil
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        },
        onDismiss: { self.selection = nil }
      )
      .padding(.bottom, showChrome ? 96 : 36)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  // MARK: Chrome

  private var chromeOverlay: some View {
    VStack {
      topBar
      Spacer()
      bottomBar
    }
    .transition(.opacity)
  }

  private var topBar: some View {
    HStack(spacing: Theme.lg) {
      Button {
        commitProgress()
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
      }
      VStack(spacing: 1) {
        Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(book.author).font(.caption2).foregroundStyle(settings.theme.textColor.opacity(0.6))
      }
      .frame(maxWidth: .infinity)
      Button {
        showContents = true
      } label: {
        Image(systemName: "list.bullet")
      }
      if book.canListen {
        Button {
          toggleReadAlong()
        } label: {
          Image(systemName: readAlong ? "text.book.closed.fill" : "text.book.closed")
            .foregroundStyle(readAlong ? Theme.accent : settings.theme.textColor)
        }
        Button {
          commitProgress()
          presentPlayer = true
        } label: {
          Image(systemName: "headphones")
        }
      }
      Button {
        showSettings = true
      } label: {
        Text("Aa").font(.system(size: 19, weight: .bold, design: .serif))
      }
    }
    .font(.title3.weight(.semibold))
    .foregroundStyle(settings.theme.textColor)
    .padding(.horizontal, Theme.lg)
    .padding(.vertical, Theme.md)
    .background(settings.theme.pageBackground.opacity(0.96))
    .overlay(alignment: .bottom) { Divider().opacity(0.4) }
  }

  private var bottomBar: some View {
    VStack(spacing: Theme.sm) {
      ThinProgressBar(progress: pageProgress)
        .padding(.horizontal, Theme.lg)
      HStack {
        Button {
          commitProgress()
          showChapterSummary = true
        } label: {
          Label(currentChapterTitle, systemImage: "sparkles")
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        Spacer()
        Text("Page \(pageIndex + 1) of \(max(1, paginator?.pageCount ?? 1))")
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(settings.theme.textColor.opacity(0.6))
      .padding(.horizontal, Theme.lg)
    }
    .padding(.vertical, Theme.md)
    .background(settings.theme.pageBackground.opacity(0.96))
    .overlay(alignment: .top) { Divider().opacity(0.4) }
  }

  private var pageProgress: Double {
    guard let paginator, paginator.pageCount > 0 else { return 0 }
    return Double(pageIndex + 1) / Double(paginator.pageCount)
  }

  private var currentChapterTitle: String {
    ChapterSummaryContent.section(for: book, offset: book.charOffset)?.title
      ?? "Chapter notes"
  }

  // MARK: Pagination + navigation

  private func repaginate(in size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    let contentSize = CGSize(
      width: size.width - pageInsets.leading - pageInsets.trailing,
      height: size.height - pageInsets.top - pageInsets.bottom
    )
    let p = Paginator.paginate(
      text: book.bodyText,
      font: settings.font.uiFont(size: settings.fontSize),
      textColor: UIColor(settings.theme.textColor),
      lineSpacing: settings.lineSpacing,
      size: contentSize
    )
    paginator = p
    pageIndex = p.pageIndex(for: book.charOffset)
  }

  private func turn(_ direction: Int) {
    guard let paginator else { return }
    selection = nil
    let next = pageIndex + direction
    guard paginator.pageRanges.indices.contains(next) else {
      if direction > 0 && next >= paginator.pageCount {
        book.isFinished = true
      }
      return
    }
    withAnimation(.easeInOut(duration: 0.18)) { pageIndex = next }
    book.charOffset = paginator.startOffset(of: next)
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
  }

  private func goToOffset(_ offset: Int) {
    guard let paginator else { return }
    pageIndex = paginator.pageIndex(for: offset)
    book.charOffset = offset
  }

  // MARK: Actions

  private func addHighlight(_ text: String, range: NSRange, color: HighlightColor) {
    let h = Highlight(
      text: text, colorName: color.rawValue,
      chapterTitle: chapterTitle(at: range.location), startOffset: range.location,
      endOffset: range.location + range.length, book: book)
    context.insert(h)
    selection = nil
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func saveNote(passage: String, range: NSRange, body: String, editing: Note?) {
    if let editing {
      editing.body = body
      try? context.save()
      selection = nil
      return
    }
    let n = Note(
      passage: passage, body: body, chapterTitle: chapterTitle(at: range.location),
      startOffset: range.location, book: book)
    context.insert(n)
    // A noted passage is also highlighted for visibility — unless one already exists there.
    let alreadyHighlighted = book.highlights.contains {
      NSLocationInRange(range.location, $0.range)
    }
    if !alreadyHighlighted {
      let h = Highlight(
        text: passage, colorName: HighlightColor.yellow.rawValue,
        chapterTitle: chapterTitle(at: range.location), startOffset: range.location,
        endOffset: range.location + range.length, book: book)
      context.insert(h)
    }
    try? context.save()
    selection = nil
  }

  /// Finds a note whose anchor falls within the highlight's range.
  private func noteFor(_ highlight: Highlight) -> Note? {
    book.notes.first { NSLocationInRange($0.startOffset, highlight.range) }
  }

  private func firstWords(_ text: String) -> String {
    text.split(separator: " ").prefix(3).joined(separator: " ")
  }

  private func chapterTitle(at offset: Int) -> String {
    ChapterSummaryContent.section(for: book, offset: offset)?.title ?? ""
  }

  // MARK: Read-along narration

  private func toggleReadAlong() {
    if readAlong {
      stopReadAlong()
    } else {
      readAlong = true
      narrator.load(text: book.bodyText, startOffset: book.charOffset)
      narrator.play()
      listenStartedAt = Date()
      withAnimation(.snappy) { showChrome = false }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
  }

  private func stopReadAlong() {
    guard readAlong else { return }
    readAlong = false
    narrator.stop()
    book.charOffset = narrator.charOffset
    if let started = listenStartedAt {
      let minutes = Int(Date().timeIntervalSince(started) / 60)
      if minutes >= 1 {
        context.insert(ReadingSession(minutes: minutes, wasListening: true))
        try? context.save()
      }
      listenStartedAt = nil
    }
  }

  private func commitProgress() {
    book.lastOpenedDate = .now
    let minutes = max(1, Int(Date().timeIntervalSince(openedAt) / 60))
    if minutes >= 1 {
      context.insert(
        ReadingSession(minutes: minutes, pagesRead: max(1, pageIndex), wasListening: false))
      openedAt = Date()
    }
    try? context.save()
  }
}

/// Wrapper so a plain String can drive `.sheet(item:)`.
struct IdentifiedString: Identifiable {
  let value: String
  var id: String { value }
  init(_ value: String) { self.value = value }
}

/// Pending note while the composer sheet is open.
struct NoteDraft: Identifiable {
  let id = UUID()
  let passage: String
  let range: NSRange
  var existingBody: String = ""
  var editingNote: Note? = nil
}

#Preview {
  ReaderView(book: PreviewData.sampleBook)
    .modelContainer(PreviewData.container)
}

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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

  @State private var settings = ReaderSettings()
  @State private var paginator: Paginator?
  @State private var pageIndex = 0
  @State private var pageSize: CGSize = .zero
  /// Keep one immutable copy for this reader session. In particular, legacy
  /// sample books otherwise rebuild their chapter string every time SwiftUI
  /// reevaluates the reader during read-along.
  @State private var readerText = ""
  @State private var didLoadReaderText = false
  @State private var paginationRequest: PaginationRequest?
  @State private var paginationGeneration = 0

  /// Only the current page's highlights are handed to UITextView. The index is
  /// refreshed after the small set of local highlight mutations below.
  @State private var highlightIndex = ReaderHighlightIndex()
  @State private var pageHighlights: [ReaderPageView.Highlight] = []
  @State private var deferredPersistenceTask: Task<Void, Never>?

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
  /// Incrementing this value restarts the deliberately short chrome timeout.
  /// VoiceOver users retain the controls rather than having them disappear.
  @State private var chromeVisibilityToken = 0

  private var pageInsets: EdgeInsets {
    EdgeInsets(top: 70, leading: settings.margins, bottom: 60, trailing: settings.margins)
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        settings.theme.pageBackground.ignoresSafeArea()

        pageLayer(in: geo.size)

        if showChrome { chromeOverlay }

        // Brightness dimming overlay (visual in-reader brightness).
        Color.black
          .opacity((1 - settings.brightness) * 0.55)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
      .overlay(alignment: .bottom) { selectionToolbarLayer }
      .onAppear {
        loadReaderTextIfNeeded()
        repaginate(in: geo.size)
        scheduleChromeFade()
      }
      .onChange(of: geo.size) { _, newSize in repaginate(in: newSize) }
      .onChange(of: settings.fontSize) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.font) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.lineSpacing) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.margins) { _, _ in repaginate(in: geo.size) }
      .onChange(of: settings.theme) { _, _ in repaginate(in: geo.size) }
      .onChange(of: pageIndex) { _, _ in refreshPageHighlights() }
    }
    .statusBarHidden(!showChrome)
    .task(id: chromeVisibilityToken) {
      guard showChrome, !voiceOverEnabled else { return }
      try? await Task.sleep(for: .seconds(4.5))
      guard !Task.isCancelled, showChrome, selection == nil,
        !showSettings, !showContents, !showChapterSummary
      else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { showChrome = false }
    }
    .task(id: paginationGeneration) {
      await paginateCurrentRequest()
    }
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
      ChapterSummaryView(book: book, initialOffset: book.canonicalCharacterOffset)
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
          rebuildHighlightIndex()
          schedulePersistence()
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
          rebuildHighlightIndex(excluding: highlight.id)
          schedulePersistence()
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
      let changedPage = target != pageIndex
      if changedPage, paginator.pageRanges.indices.contains(target) {
        withAnimation(.easeInOut(duration: 0.2)) { pageIndex = target }
      }
      if abs(book.charOffset - range.location) >= 500 || changedPage {
        // Speech callbacks arrive for every word. Avoid dirtying the SwiftData
        // book object at that rate while still retaining frequent checkpoints.
        book.updateCharacterOffset(range.location, allowingBackward: true)
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
        highlights: pageHighlights,
        activeWordRange: readAlong ? narrator.spokenWordRange : nil,
        onSelect: { text, range in
          selection = (text, range)
          UISelectionFeedbackGenerator().selectionChanged()
        },
        accessibilityPageDescription: "Page \(pageIndex + 1) of \(paginator.pageCount)",
        onTapHighlight: { highlightID in
          if let hit = highlightIndex.highlight(withID: highlightID) {
            selection = nil
            activeHighlight = hit
            UISelectionFeedbackGenerator().selectionChanged()
          }
        },
        onTapZone: { zone in
          switch zone {
          case .left: turn(-1)
          case .center: toggleChrome()
          case .right: turn(1)
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
        onDismiss: { self.selection = nil },
        shareText: selection.text
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
    .transition(.opacity.combined(with: .move(edge: .top)))
    .accessibilityElement(children: .contain)
  }

  private var topBar: some View {
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
          .foregroundStyle(settings.theme.textColor.opacity(0.58))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(book.title) by \(book.author)")
      ReaderChromeButton(systemImage: "list.bullet", label: "Table of contents") {
        showContents = true
      }
      if book.canListen {
        ReaderChromeButton(
          systemImage: readAlong ? "text.book.closed.fill" : "text.book.closed",
          label: readAlong ? "Stop read along" : "Start read along",
          isActive: readAlong
        ) {
          toggleReadAlong()
        }
        ReaderChromeButton(systemImage: "headphones", label: "Open audio player") {
          commitProgress()
          presentPlayer = true
        }
      }
      ReaderChromeButton(systemImage: "textformat.size", label: "Reading settings") {
        showSettings = true
      }
    }
    .foregroundStyle(settings.theme.textColor)
    .padding(.horizontal, Theme.lg)
    .padding(.vertical, Theme.sm)
    .background(settings.theme.pageBackground.opacity(0.88))
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Rectangle().fill(settings.theme.textColor.opacity(0.09)).frame(height: 0.5)
    }
  }

  private var bottomBar: some View {
    VStack(spacing: Theme.md) {
      Button {
        commitProgress()
        showChapterSummary = true
      } label: {
        ReaderProgressFooter(
          progress: pageProgress,
          title: currentChapterTitle,
          detail: "Page \(pageIndex + 1) of \(max(1, paginator?.pageCount ?? 1))",
          foreground: settings.theme.textColor
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(currentChapterTitle), \(Int(pageProgress * 100)) percent complete")
      .accessibilityHint("Opens chapter notes and summary")

      if book.canListen {
        ReaderAudioHandoff(
          title: readAlong ? "Read along is active" : "Listen from this page",
          progress: pageProgress,
          foreground: settings.theme.textColor
        ) {
          if readAlong { stopReadAlong() }
          commitProgress()
          presentPlayer = true
        }
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.md)
    .background(settings.theme.pageBackground.opacity(0.88))
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle().fill(settings.theme.textColor.opacity(0.09)).frame(height: 0.5)
    }
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
    loadReaderTextIfNeeded()
    let contentSize = CGSize(
      width: size.width - pageInsets.leading - pageInsets.trailing,
      height: size.height - pageInsets.top - pageInsets.bottom
    )
    let request = PaginationRequest(
      key: PaginatorCache.Key(
        bookID: book.id,
        textLength: (readerText as NSString).length,
        fontName: settings.font.rawValue,
        fontSize: settings.fontSize,
        textColorKey: settings.theme.rawValue,
        lineSpacing: settings.lineSpacing,
        width: contentSize.width,
        height: contentSize.height),
      text: readerText,
      font: settings.font.uiFont(size: settings.fontSize),
      textColor: UIColor(settings.theme.textColor),
      lineSpacing: settings.lineSpacing,
      size: contentSize)

    if let cached = PaginatorCache.shared.paginator(for: request.key) {
      // Invalidate a still-running layout for a previous setting/size before
      // installing the cache hit; otherwise its eventual result could replace
      // this page after the user has already moved on.
      paginationRequest = nil
      paginationGeneration &+= 1
      applyPaginator(cached)
      return
    }

    paginationRequest = request
    paginationGeneration &+= 1
  }

  private func paginateCurrentRequest() async {
    guard let request = paginationRequest else { return }
    if let cached = PaginatorCache.shared.paginator(for: request.key) {
      applyPaginator(cached)
      return
    }
    guard let result = await Paginator.paginateInBackground(
      text: request.text, font: request.font, textColor: request.textColor,
      lineSpacing: request.lineSpacing, size: request.size), !Task.isCancelled,
      paginationRequest?.key == request.key
    else { return }
    PaginatorCache.shared.insert(result, for: request.key)
    applyPaginator(result)
  }

  private func applyPaginator(_ paginator: Paginator) {
    book.restoreCanonicalCharacterOffset()
    self.paginator = paginator
    pageIndex = paginator.pageIndex(for: book.canonicalCharacterOffset)
    refreshPageHighlights()
  }

  private func loadReaderTextIfNeeded() {
    guard !didLoadReaderText else { return }
    readerText = book.bodyText
    didLoadReaderText = true
    book.restoreCanonicalCharacterOffset()
    rebuildHighlightIndex()
  }

  private func rebuildHighlightIndex(excluding deletedID: UUID? = nil) {
    let highlights = deletedID.map { id in book.highlights.filter { $0.id != id } }
      ?? book.highlights
    highlightIndex = ReaderHighlightIndex(highlights)
    refreshPageHighlights()
  }

  private func refreshPageHighlights() {
    guard let paginator, paginator.pageRanges.indices.contains(pageIndex) else {
      pageHighlights = []
      return
    }
    pageHighlights = highlightIndex.highlights(intersecting: paginator.pageRanges[pageIndex])
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
    // A page turn is explicit reader navigation, so going back intentionally
    // is allowed. Cross-mode commits retain the monotonic default instead.
    book.updateCharacterOffset(paginator.startOffset(of: next), allowingBackward: true)
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
  }

  private func goToOffset(_ offset: Int) {
    guard let paginator else { return }
    pageIndex = paginator.pageIndex(for: offset)
    book.updateCharacterOffset(offset, allowingBackward: true)
  }

  // MARK: Actions

  private func addHighlight(_ text: String, range: NSRange, color: HighlightColor) {
    let h = Highlight(
      text: text, colorName: color.rawValue,
      chapterTitle: chapterTitle(at: range.location), startOffset: range.location,
      endOffset: range.location + range.length, book: book)
    context.insert(h)
    rebuildHighlightIndex()
    schedulePersistence()
    selection = nil
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func saveNote(passage: String, range: NSRange, body: String, editing: Note?) {
    if let editing {
      editing.body = body
      schedulePersistence()
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
    rebuildHighlightIndex()
    schedulePersistence()
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
      narrator.load(text: readerText, startOffset: book.canonicalCharacterOffset)
      narrator.play()
      listenStartedAt = Date()
      withAnimation(reduceMotion ? nil : .snappy) { showChrome = false }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
  }

  private func stopReadAlong() {
    guard readAlong else { return }
    readAlong = false
    narrator.stop()
    book.updateCharacterOffset(narrator.charOffset, allowingBackward: true)
    if let started = listenStartedAt {
      let minutes = Int(Date().timeIntervalSince(started) / 60)
      if minutes >= 1 {
        context.insert(ReadingSession(minutes: minutes, wasListening: true))
      }
      listenStartedAt = nil
      flushDeferredPersistence()
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
    flushDeferredPersistence()
  }

  /// Highlight actions should feel immediate, but synchronously flushing the
  /// entire SwiftData graph for every color tap can hitch the reader. Batch a
  /// short burst, while `commitProgress` still flushes before every handoff.
  private func schedulePersistence() {
    deferredPersistenceTask?.cancel()
    deferredPersistenceTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(300))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      try? context.save()
    }
  }

  private func flushDeferredPersistence() {
    deferredPersistenceTask?.cancel()
    deferredPersistenceTask = nil
    try? context.save()
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
}

/// Immutable input captured on the main actor before a utility pagination task
/// begins. It never carries a SwiftData model into the worker.
private struct PaginationRequest {
  let key: PaginatorCache.Key
  let text: String
  let font: UIFont
  let textColor: UIColor
  let lineSpacing: CGFloat
  let size: CGSize
}

/// Captures the reader's highlight relationship once, then uses prefix maximum
/// end offsets to find the few highlights intersecting a page. This also gives
/// the tap handler constant-time access to its SwiftData model.
private struct ReaderHighlightIndex {
  private struct Entry {
    let id: UUID
    let range: NSRange
    let color: UIColor
  }

  private let entries: [Entry]
  private let prefixEndOffsets: [Int]
  private let highlightsByID: [UUID: Highlight]

  init(_ highlights: [Highlight] = []) {
    let sorted = highlights.sorted {
      if $0.startOffset != $1.startOffset { return $0.startOffset < $1.startOffset }
      return $0.id.uuidString < $1.id.uuidString
    }
    entries = sorted.map {
      Entry(
        id: $0.id, range: $0.range,
        color: (HighlightColor(rawValue: $0.colorName) ?? .yellow).uiColor)
    }
    var maximumEnd = 0
    prefixEndOffsets = entries.map {
      maximumEnd = max(maximumEnd, $0.range.location + $0.range.length)
      return maximumEnd
    }
    highlightsByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
  }

  func highlights(intersecting page: NSRange) -> [ReaderPageView.Highlight] {
    let pageEnd = page.location + page.length
    var index = firstEntry(withEndAfter: page.location)
    var result: [ReaderPageView.Highlight] = []
    while index < entries.count, entries[index].range.location < pageEnd {
      let entry = entries[index]
      if entry.range.location + entry.range.length > page.location {
        result.append(ReaderPageView.Highlight(id: entry.id, range: entry.range, color: entry.color))
      }
      index += 1
    }
    return result
  }

  func highlight(withID id: UUID) -> Highlight? {
    highlightsByID[id]
  }

  /// The first entry whose preceding maximum end reaches into this page.
  private func firstEntry(withEndAfter offset: Int) -> Int {
    var lower = 0
    var upper = prefixEndOffsets.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if prefixEndOffsets[middle] > offset {
        upper = middle
      } else {
        lower = middle + 1
      }
    }
    return lower
  }
}

/// A consistent, generously-sized reader action target. The visual treatment is
/// intentionally quiet so the page remains the primary surface.
struct ReaderChromeButton: View {
  let systemImage: String
  let label: String
  var isActive = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 36, height: 36)
        .background(isActive ? Theme.accent.opacity(0.16) : .clear, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// Shared chapter / completion treatment for text, EPUB, and PDF readers.
struct ReaderProgressFooter: View {
  let progress: Double
  let title: String
  let detail: String
  let foreground: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ThinProgressBar(progress: min(1, max(0, progress)))
        .frame(height: 3)
      HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
        Label(title, systemImage: "text.book.closed")
          .lineLimit(1)
        Spacer(minLength: Theme.sm)
        Text(detail)
          .monospacedDigit()
          .lineLimit(1)
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(foreground.opacity(0.68))
    }
  }
}

/// A compact handoff into the full audio player. It makes the read/listen
/// relationship visible without turning the reader into a playback screen.
struct ReaderAudioHandoff: View {
  let title: String
  let progress: Double
  let foreground: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.sm) {
        Image(systemName: "headphones")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(Theme.accent, in: Circle())
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Text("Continue at \(Int(min(1, max(0, progress)) * 100))%")
            .font(.caption2)
            .foregroundStyle(foreground.opacity(0.58))
        }
        Spacer(minLength: Theme.sm)
        Image(systemName: "play.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(Theme.accent)
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, Theme.sm)
      .padding(.vertical, 7)
      .background(foreground.opacity(0.07), in: Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(title). Continue listening at \(Int(min(1, max(0, progress)) * 100)) percent")
    .accessibilityHint("Opens the audio player")
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

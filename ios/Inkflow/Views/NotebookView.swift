import SwiftData
import SwiftUI
import UIKit

/// Notebook hub — every highlight and note across the library, with search,
/// color filtering, per-book grouping, copy, share/export, and inline delete.
struct NotebookView: View {
  @Query(sort: \Highlight.createdDate, order: .reverse) private var highlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var notes: [Note]
  @Query private var books: [Book]
  @Environment(\.modelContext) private var context

  @State private var workspace: Workspace = .notes
  @State private var filter: Filter = .all
  @State private var searchText = ""
  @State private var colorFilter: HighlightColor?
  @State private var summaryBook: Book?
  @FocusState private var searchFocused: Bool

  enum Workspace: String, CaseIterable, Identifiable {
    case notes = "Notes"
    case summaries = "Summaries"
    var id: String { rawValue }
  }

  enum Filter: String, CaseIterable {
    case all = "All"
    case highlights = "Highlights"
    case notes = "Notes"
  }

  /// A unified annotation entry so highlights and notes sort together per book.
  private struct Entry: Identifiable {
    enum Kind {
      case highlight(Highlight)
      case note(Note)
    }
    let id: String
    let kind: Kind
    let bookTitle: String
    let chapter: String
    let date: Date
    let searchBlob: String
    let color: HighlightColor?
  }

  private var entries: [Entry] {
    var items: [Entry] = []
    if filter != .notes {
      for h in highlights {
        let color = HighlightColor(rawValue: h.colorName)
        items.append(
          Entry(
            id: "h-\(h.id)", kind: .highlight(h),
            bookTitle: h.book?.title ?? "Unknown", chapter: h.chapterTitle,
            date: h.createdDate, searchBlob: "\(h.text) \(h.book?.title ?? "")".lowercased(),
            color: color))
      }
    }
    if filter != .highlights {
      for n in notes {
        items.append(
          Entry(
            id: "n-\(n.id)", kind: .note(n),
            bookTitle: n.book?.title ?? "Unknown", chapter: n.chapterTitle,
            date: n.createdDate,
            searchBlob: "\(n.passage) \(n.body) \(n.book?.title ?? "")".lowercased(),
            color: nil))
      }
    }
    let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
    return
      items
      .filter { q.isEmpty || $0.searchBlob.contains(q) }
      .filter { entry in
        guard let colorFilter else { return true }
        return entry.color == colorFilter
      }
      .sorted { $0.date > $1.date }
  }

  private var grouped: [(book: String, entries: [Entry])] {
    let dict = Dictionary(grouping: entries, by: \.bookTitle)
    return
      dict
      .map { (book: $0.key, entries: $0.value) }
      .sorted {
        ($0.entries.first?.date ?? .distantPast) > ($1.entries.first?.date ?? .distantPast)
      }
  }

  private var isEmpty: Bool { highlights.isEmpty && notes.isEmpty }

  var body: some View {
    Group {
      NavigationStack {
        VStack(spacing: 0) {
          ScreenHeader("Notebook") {
            if workspace == .notes, !isEmpty {
              ShareLink(item: exportText) {
                Image(systemName: "square.and.arrow.up")
                  .font(.title3.weight(.semibold))
                  .foregroundStyle(Theme.accent)
                  .frame(width: 32, height: 32)
              }
            }
          }

          Picker("Notebook workspace", selection: $workspace) {
            ForEach(Workspace.allCases) { item in Text(item.rawValue).tag(item) }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal, Theme.lg)
          .padding(.bottom, Theme.sm)

          if workspace == .summaries || !isEmpty {
            InlineSearchField(
              prompt: workspace == .notes ? "Search highlights & notes" : "Search books",
              text: $searchText, focused: $searchFocused)
          }
          Group {
            if workspace == .summaries {
              summariesContent
            } else if isEmpty {
              emptyState
            } else {
              content
            }
          }
        }
        .background(Theme.paper)
      }
    }
    .sheet(item: $summaryBook) { book in
      ChapterSummaryView(
        book: book, initialOffset: summaryOffset(for: book), initialTab: .summary
      )
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .__tenxTrackView("NotebookView")
  }

  // MARK: Summaries

  private var summaryBooks: [Book] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return books
      .filter { $0.bodyNSLength > 0 }
      .filter {
        query.isEmpty || $0.title.lowercased().contains(query)
          || $0.author.lowercased().contains(query)
      }
      .sorted {
        ($0.lastOpenedDate ?? $0.addedDate) > ($1.lastOpenedDate ?? $1.addedDate)
      }
  }

  private var summariesContent: some View {
    Group {
      if summaryBooks.isEmpty {
        ContentUnavailableView {
          Label(
            books.isEmpty ? "Your chapter guides live here" : "No matching books",
            systemImage: "sparkles.rectangle.stack")
        } description: {
          Text(
            books.isEmpty
              ? "Add a book, then ReadSync will organize its extracted text into chapter summaries and space for your own thoughts."
              : "Try a different title or author."
          )
        }
      } else {
        ScrollView {
          LazyVStack(spacing: Theme.lg) {
            ForEach(summaryBooks) { book in
              summaryCard(for: book)
            }
            Color.clear.frame(height: Theme.lg)
          }
          .padding(Theme.lg)
        }
      }
    }
  }

  private func summaryCard(for book: Book) -> some View {
    let section = ChapterSummaryContent.section(for: book, offset: summaryOffset(for: book))
    return VStack(alignment: .leading, spacing: Theme.md) {
      HStack(spacing: Theme.md) {
        BookCover(book: book, width: 48, showAudioBadge: false)
        VStack(alignment: .leading, spacing: 3) {
          Text(book.title)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(section?.title ?? "Chapter guide")
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "sparkles")
          .foregroundStyle(Theme.accent)
      }

      if let section {
        ChapterSummaryMarkdownView(markdown: ChapterSummaryContent.markdown(for: section))
      }

      Button {
        summaryBook = book
      } label: {
        HStack {
          Text("Open chapter guide")
          Spacer()
          Image(systemName: "arrow.right")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline))
  }

  private func summaryOffset(for book: Book) -> Int {
    if book.format == .text { return book.charOffset }
    return Int(Double(book.bodyNSLength) * book.progress)
  }

  private var content: some View {
    ScrollView {
      VStack(spacing: Theme.md) {
        Picker("", selection: $filter) {
          ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.lg)
        .padding(.top, Theme.sm)

        if filter != .notes { colorFilterBar }

        if entries.isEmpty {
          noMatchState
        } else {
          ForEach(grouped, id: \.book) { group in
            bookSection(group.book, entries: group.entries)
          }
        }
        Color.clear.frame(height: Theme.lg)
      }
      .padding(.horizontal, Theme.lg)
    }
  }

  private var colorFilterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Theme.sm) {
        colorChip(nil, label: "All colors")
        ForEach(HighlightColor.allCases) { color in
          colorChip(color, label: color.rawValue.capitalized)
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func colorChip(_ color: HighlightColor?, label: String) -> some View {
    let active = colorFilter == color
    return Button {
      withAnimation(.snappy) { colorFilter = (color == colorFilter) ? nil : color }
    } label: {
      HStack(spacing: 6) {
        if let color {
          Circle().fill(color.color).frame(width: 12, height: 12)
        }
        Text(label).font(.subheadline.weight(.medium))
      }
      .foregroundStyle(active ? .white : Theme.ink)
      .padding(.horizontal, Theme.md)
      .padding(.vertical, 7)
      .background(active ? Theme.accent : Theme.surfaceAlt, in: Capsule())
    }
  }

  private func bookSection(_ title: String, entries: [Entry]) -> some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      HStack(spacing: 6) {
        Image(systemName: "book.closed").font(.caption)
        Text(title).font(.subheadline.weight(.bold))
        Spacer()
        Text("\(entries.count)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(Theme.inkFaint)
      }
      .foregroundStyle(Theme.ink)
      .padding(.top, Theme.sm)

      ForEach(entries) { entry in
        switch entry.kind {
        case .highlight(let h): highlightCard(h)
        case .note(let n): noteCard(n)
        }
      }
    }
  }

  // MARK: Cards

  private func highlightCard(_ highlight: Highlight) -> some View {
    let color = HighlightColor(rawValue: highlight.colorName)?.color ?? Theme.highlightYellow
    return HStack(alignment: .top, spacing: Theme.md) {
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5)
      VStack(alignment: .leading, spacing: Theme.sm) {
        Text(highlight.text)
          .font(.callout)
          .foregroundStyle(Theme.ink)
          .fixedSize(horizontal: false, vertical: true)
        metaRow(chapter: highlight.chapterTitle, date: highlight.createdDate)
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
    .contextMenu {
      Button {
        UIPasteboard.general.string = highlight.text
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }
      Button(role: .destructive) {
        context.delete(highlight)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private func noteCard(_ note: Note) -> some View {
    HStack(alignment: .top, spacing: Theme.md) {
      Image(systemName: "note.text")
        .foregroundStyle(Theme.accent)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: Theme.sm) {
        Text(note.passage)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Theme.ink)
        if !note.body.isEmpty {
          ChapterSummaryMarkdownView(markdown: note.body)
        }
        metaRow(chapter: note.chapterTitle, date: note.createdDate)
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
    .contextMenu {
      Button {
        UIPasteboard.general.string =
          note.body.isEmpty ? note.passage : "\(note.passage)\n\n\(note.body)"
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }
      Button(role: .destructive) {
        context.delete(note)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private func metaRow(chapter: String, date: Date) -> some View {
    HStack(spacing: 6) {
      if !chapter.isEmpty {
        Text(chapter).lineLimit(1)
        Text("·")
      }
      Text(date, format: .dateTime.month().day().year())
      Spacer()
    }
    .font(.caption2)
    .foregroundStyle(Theme.inkFaint)
  }

  // MARK: States

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No notes yet", systemImage: "bookmark")
    } description: {
      Text(
        "Long-press any passage while reading to highlight it or add a note. Tap a highlight again to recolor or annotate it. Everything collects here."
      )
    }
  }

  private var noMatchState: some View {
    VStack(spacing: Theme.sm) {
      Image(systemName: "magnifyingglass")
        .font(.largeTitle)
        .foregroundStyle(Theme.inkFaint)
      Text("No matching annotations")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      Text("Try a different search or color filter.")
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Theme.xl * 2)
  }

  // MARK: Export

  private var exportText: String {
    var lines: [String] = ["My ReadSync Notebook", ""]
    for group in grouped {
      lines.append("# \(group.book)")
      for entry in group.entries {
        switch entry.kind {
        case .highlight(let h):
          lines.append("• \(h.text)")
        case .note(let n):
          lines.append("• \(n.passage)")
          if !n.body.isEmpty { lines.append("    Note: \(n.body)") }
        }
      }
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }
}

#Preview {
  NotebookView()
    .modelContainer(PreviewData.container)
}

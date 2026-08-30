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
      BookSummaryListView(book: book, initialOffset: summaryOffset(for: book))
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .__tenxTrackView("NotebookView")
  }

  // MARK: Summaries

  private var summaryBooks: [Book] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return books
      .filter { $0.bodyNSLength > 0 || $0.isEpub }
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
            books.isEmpty ? "Your chapter summaries live here" : "No matching books",
            systemImage: "sparkles.rectangle.stack")
        } description: {
          Text(
            books.isEmpty
              ? "Add a book, then Inkflow will detect its chapters and keep a two-sentence recap for each one."
              : "Try a different title or author, or clear your search."
          )
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: Theme.lg) {
            VStack(alignment: .leading, spacing: Theme.xs) {
              Text("SUMMARIES BY BOOK")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(Theme.inkFaint)
              Text("Return to every chapter in a minute.")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            }
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
    let sections = ChapterSummaryContent.sections(for: book)
    let current = ChapterSummaryContent.section(for: book, offset: summaryOffset(for: book))
    return Button {
      summaryBook = book
    } label: {
      HStack(spacing: Theme.md) {
        BookCover(book: book, width: 52, showAudioBadge: false)
        VStack(alignment: .leading, spacing: Theme.xs) {
          Text("\(sections.count) \(sections.count == 1 ? "CHAPTER" : "CHAPTERS") DETECTED")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(Theme.accent)
          Text(book.title)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
          Text(current.map { "Current: \($0.title)" } ?? "Open chapter summaries")
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.bold))
          .frame(width: 30, height: 30)
          .background(Theme.surfaceAlt, in: Circle())
          .foregroundStyle(Theme.accent)
      }
    }
    .buttonStyle(.plain)
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
        Picker("Show", selection: $filter) {
          ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.lg)
        .padding(.top, Theme.sm)

        if filter != .notes { colorFilterBar }

        annotationsSummary

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

  private var annotationsSummary: some View {
    HStack(spacing: Theme.sm) {
      Text("\(entries.count) \(entries.count == 1 ? "thought" : "thoughts")")
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.ink)
      if !searchText.isEmpty || colorFilter != nil || filter != .all {
        Text("·")
          .foregroundStyle(Theme.inkFaint)
        Button("Clear filters") {
          withAnimation(.snappy) {
            searchText = ""
            colorFilter = nil
            filter = .all
          }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.accent)
      }
      Spacer()
    }
    .padding(.top, Theme.xs)
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
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack(spacing: 6) {
        Image(systemName: "book.closed.fill").font(.caption)
        Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
        Spacer()
        Text("\(entries.count)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(Theme.inkFaint)
      }
      .foregroundStyle(Theme.ink)
      .padding(.top, Theme.md)

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
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4)
      VStack(alignment: .leading, spacing: Theme.md) {
        HStack(spacing: Theme.xs) {
          Text("HIGHLIGHT")
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.inkFaint)
          Spacer()
          Image(systemName: "highlighter")
            .font(.caption)
            .foregroundStyle(color)
        }
        Text(highlight.text)
          .font(.system(.body, design: .serif))
          .foregroundStyle(Theme.ink)
          .lineSpacing(3)
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
      VStack(alignment: .leading, spacing: Theme.md) {
        HStack {
          Text("YOUR NOTE")
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.accent)
          Spacer()
        }
        if !note.passage.isEmpty {
          Text(note.passage)
            .font(.system(.callout, design: .serif).italic())
            .foregroundStyle(Theme.inkSoft)
            .lineSpacing(2)
            .padding(.leading, Theme.md)
            .overlay(alignment: .leading) {
              Capsule().fill(Theme.accent.opacity(0.6)).frame(width: 3)
            }
        }
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
      Label("Your reading will leave a trail", systemImage: "bookmark")
    } description: {
      Text(
        "Long-press a passage to save a highlight or write a note. The ideas worth returning to will gather here, organized by book."
      )
    }
  }

  private var noMatchState: some View {
    VStack(spacing: Theme.sm) {
      Image(systemName: "magnifyingglass")
        .font(.largeTitle)
        .foregroundStyle(Theme.inkFaint)
      Text("No matching thoughts")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      Text("Try another phrase or clear a filter to see your saved ideas.")
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Theme.xl * 2)
  }

  // MARK: Export

  private var exportText: String {
    var lines: [String] = ["My Inkflow Notebook", ""]
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

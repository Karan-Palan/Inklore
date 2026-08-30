import SwiftData
import SwiftUI

/// Chapter / position list for the reader. For downloaded books without real
/// chapter markers it offers quick jumps through the book by percentage.
struct ChapterListSheet: View {
  let book: Book
  let onSelect: (Int) -> Void
  @Environment(\.dismiss) private var dismiss

  private var hasChapters: Bool { !book.chapters.isEmpty && book.storedText.isEmpty }

  var body: some View {
    NavigationStack {
      List {
        if hasChapters {
          Section("Chapters") {
            ForEach(book.chapters.indices, id: \.self) { index in
              Button {
                onSelect(chapterOffset(index))
              } label: {
                Text(book.chapters[index].title).foregroundStyle(Theme.ink)
              }
            }
          }
        } else {
          Section("Jump to") {
            ForEach(Array(stride(from: 0, through: 90, by: 10)), id: \.self) { pct in
              Button {
                onSelect(Int(Double(book.bodyNSLength) * Double(pct) / 100))
              } label: {
                HStack {
                  Text("\(pct)%").foregroundStyle(Theme.ink)
                  Spacer()
                  if Int(book.progress * 100) >= pct && Int(book.progress * 100) < pct + 10 {
                    Image(systemName: "book.fill").foregroundStyle(Theme.accent)
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle("Contents")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }.tint(Theme.accent)
        }
      }
    }
  }

  /// Approximate character offset of a chapter heading within the assembled body.
  private func chapterOffset(_ index: Int) -> Int {
    let body = book.bodyText as NSString
    let heading = book.chapters[index].title
    let r = body.range(of: heading)
    return r.location == NSNotFound ? 0 : r.location
  }
}

/// Small composer for attaching a note to a highlighted passage.
struct NoteComposer: View {
  let passage: String
  var initialText: String = ""
  let onSave: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.lg) {
        Text(passage)
          .font(.callout.italic())
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(3)
          .padding(Theme.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusSm))

        TextField("Add your note…", text: $text, axis: .vertical)
          .lineLimit(3...6)
          .padding(Theme.md)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.hairline))

        Spacer(minLength: 0)
      }
      .padding(Theme.lg)
      .background(Theme.paper)
      .navigationTitle("New note")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { if text.isEmpty { text = initialText } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
          }
          .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }
}

// MARK: - Chapter summaries + thoughts

/// A chapter-like slice of the extracted book text. The summary UI consumes this
/// value today; a server summary endpoint can consume the same `text` and stable
/// `id` later without changing the reader screens.
struct ChapterSummarySection: Identifiable, Equatable {
  let id: String
  let title: String
  let text: String
  let startOffset: Int
  let endOffset: Int
}

/// Deterministic chapter discovery and preview summary generation. This is a
/// deliberate local fallback while the AI endpoint is not wired: it never
/// invents book facts, works offline, and only uses the imported chapter text.
enum ChapterSummaryContent {
  static func sections(for book: Book) -> [ChapterSummarySection] {
    if book.isEpub, !book.epubFolderName.isEmpty,
      let document = EpubDocument(folderName: book.epubFolderName)
    {
      let epubSections = epubSections(for: book, document: document)
      if !epubSections.isEmpty { return epubSections }
    }

    if book.storedText.isEmpty, !book.chapters.isEmpty {
      return structuredSections(for: book)
    }

    let text = book.bodyText
    let nsText = text as NSString
    guard nsText.length > 0 else { return [] }

    let headingPattern =
      #"(?im)^\s*(?:#{1,3}\s*)?(?:chapter|part|book)\s+(?:[0-9ivxlcdm]+|[a-z][a-z0-9-]*)(?:\s*[:.\-–—]\s*[^\n]{0,90}|\s+[^\n]{0,90})?\s*$"#
    let regex = try? NSRegularExpression(pattern: headingPattern)
    let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

    if matches.count >= 2 {
      return matches.enumerated().map { index, match in
        let start = match.range.location
        let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
        let rawTitle = nsText.substring(with: match.range)
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: #"^#{1,3}\s*"#, with: "", options: .regularExpression)
        let bodyStart = min(NSMaxRange(match.range), end)
        let body = nsText.substring(with: NSRange(location: bodyStart, length: end - bodyStart))
        return ChapterSummarySection(
          id: "\(book.id.uuidString)-\(start)",
          title: rawTitle.isEmpty ? "Chapter \(index + 1)" : rawTitle,
          text: body,
          startOffset: start,
          endOffset: end)
      }
    }

    return fallbackSections(for: book, text: nsText)
  }

  static func section(for book: Book, offset: Int) -> ChapterSummarySection? {
    let candidates = sections(for: book)
    guard !candidates.isEmpty else { return nil }
    if book.isEpub, candidates.indices.contains(book.spineIndex) {
      return candidates[book.spineIndex]
    }
    let safeOffset = max(0, offset)
    return candidates.first { safeOffset >= $0.startOffset && safeOffset < $0.endOffset }
      ?? candidates.last
  }

  static func markdown(for section: ChapterSummarySection) -> String {
    let source = summaryBody(in: section.text, chapterTitle: section.title)
    return conciseMarkdown(title: section.title, source: source, fallback: source)
  }

  /// The summary contract everywhere in the app: one chapter heading followed
  /// by exactly two short, source-grounded sentences. AI output is normalized
  /// through the same renderer so a verbose provider response cannot reintroduce
  /// the old multi-section guide UI.
  static func markdown(for section: ChapterSummarySection, generatedText: String?) -> String {
    guard let generatedText, !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return markdown(for: section) }
    return conciseMarkdown(
      title: section.title,
      source: summaryBody(in: generatedText, chapterTitle: section.title),
      fallback: summaryBody(in: section.text, chapterTitle: section.title))
  }

  private static func summaryBody(in text: String, chapterTitle: String) -> String {
    let normalizedTitle = chapterTitle
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let keptLines = text.components(separatedBy: .newlines).compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      let withoutMarkdown = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#>-• \t"))
      guard !withoutMarkdown.isEmpty,
        withoutMarkdown.lowercased() != normalizedTitle,
        !trimmed.hasPrefix("#")
      else { return nil }
      return withoutMarkdown
    }
    return keptLines.joined(separator: " ")
  }

  private static func conciseMarkdown(title: String, source: String, fallback: String) -> String {
    var sentences = sentenceList(from: source)
    if sentences.count < 2 {
      sentences += sentenceList(from: fallback).filter { candidate in
        !sentences.contains(candidate)
      }
    }
    if sentences.isEmpty {
      sentences = [
        "No extractable text was found for this chapter yet.",
        "Try re-importing the source with text recognition enabled.",
      ]
    } else if sentences.count == 1 {
      sentences.append("The available text is brief, so this summary stays close to the chapter's opening idea.")
    }

    let selected = selectTwoSentences(from: sentences)
    return "# \(title)\n\n\(selected.joined(separator: "\n\n"))"
  }

  private static func selectTwoSentences(from sentences: [String]) -> [String] {
    guard let opening = sentences.first else { return [] }
    let keywords = frequentTerms(in: sentences.joined(separator: " "))
    let ranked = sentences.enumerated().sorted { lhs, rhs in
      sentenceScore(lhs.element, keywords: keywords, position: lhs.offset)
        > sentenceScore(rhs.element, keywords: keywords, position: rhs.offset)
    }
    let second = ranked.map(\.element).first { $0 != opening } ?? sentences.dropFirst().first ?? opening
    return [opening, second]
  }

  private static func structuredSections(for book: Book) -> [ChapterSummarySection] {
    var offset = 0
    return book.chapters.enumerated().map { index, chapter in
      let assembled = chapter.title + "\n\n" + chapter.paragraphs.joined(separator: "\n\n")
      let length = (assembled as NSString).length
      defer { offset += length + (index == book.chapters.count - 1 ? 0 : 3) }
      return ChapterSummarySection(
        id: "\(book.id.uuidString)-\(offset)",
        title: chapter.title,
        text: chapter.paragraphs.joined(separator: "\n\n"),
        startOffset: offset,
        endOffset: offset + length)
    }
  }

  private static func epubSections(for book: Book, document: EpubDocument) -> [ChapterSummarySection] {
    var offset = 0
    return document.chapters.enumerated().map { index, chapter in
      let text = document.text(for: chapter)
      let length = (text as NSString).length
      defer { offset += length + (index == document.chapters.count - 1 ? 0 : 2) }
      return ChapterSummarySection(
        id: "\(book.id.uuidString)-epub-\(index)",
        title: chapter.title,
        text: text,
        startOffset: offset,
        endOffset: offset + length)
    }
  }

  private static func fallbackSections(for book: Book, text: NSString) -> [ChapterSummarySection] {
    let targetLength = 12_000
    if text.length <= targetLength + 3_000 {
      return [
        ChapterSummarySection(
          id: "\(book.id.uuidString)-0", title: "Whole book", text: text as String,
          startOffset: 0, endOffset: text.length)
      ]
    }

    var result: [ChapterSummarySection] = []
    var start = 0
    while start < text.length {
      var end = min(text.length, start + targetLength)
      if end < text.length {
        let searchLength = min(1_500, text.length - end)
        let breakRange = text.range(
          of: "\n\n", options: [], range: NSRange(location: end, length: searchLength))
        if breakRange.location != NSNotFound { end = breakRange.location }
      }
      if end <= start { end = min(text.length, start + targetLength) }
      let number = result.count + 1
      result.append(
        ChapterSummarySection(
          id: "\(book.id.uuidString)-\(start)",
          title: "Section \(number)",
          text: text.substring(with: NSRange(location: start, length: end - start)),
          startOffset: start,
          endOffset: end))
      start = end
      while start < text.length,
        CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: start))!)
      {
        start += 1
      }
    }
    return result
  }

  private static func sentenceList(from text: String) -> [String] {
    let limited = String(text.prefix(80_000))
    var result: [String] = []
    limited.enumerateSubstrings(
      in: limited.startIndex..<limited.endIndex,
      options: [.bySentences, .substringNotRequired]
    ) { _, range, _, _ in
      let value = limited[range]
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if value.count >= 12, value.count <= 300 { result.append(value) }
    }
    if result.isEmpty {
      let fallback = limited
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !fallback.isEmpty { result.append(String(fallback.prefix(280))) }
    }
    return result
  }

  private static func frequentTerms(in text: String) -> [String] {
    let stopWords: Set<String> = [
      "about", "after", "again", "also", "because", "been", "before", "being", "between",
      "could", "does", "from", "have", "into", "just", "more", "most", "much", "only",
      "other", "over", "said", "some", "such", "than", "that", "their", "them", "then",
      "there", "these", "they", "this", "those", "through", "very", "what", "when", "where",
      "which", "while", "will", "with", "would", "your",
    ]
    let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
    var counts: [String: Int] = [:]
    for word in words where word.count >= 5 && !stopWords.contains(word) {
      counts[word, default: 0] += 1
    }
    return counts.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(10).map(\.key)
  }

  private static func sentenceScore(_ sentence: String, keywords: [String], position: Int) -> Double {
    let lower = sentence.lowercased()
    let hits = keywords.prefix(8).reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
    let openingBonus = position == 0 ? 2.5 : 0
    return Double(hits) + openingBonus - Double(sentence.count) / 1_000
  }
}

/// Lightweight native Markdown renderer for summaries and notes. It supports
/// block headings, bullets, quotes and code plus Swift's inline Markdown parser.
struct ChapterSummaryMarkdownView: View {
  let markdown: String

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func blockView(_ block: Block) -> some View {
    switch block {
    case .heading(let level, let value):
      inlineText(value)
        .font(level == 1 ? .title2.weight(.bold) : .headline.weight(.bold))
        .foregroundStyle(Theme.ink)
        .padding(.top, level == 1 ? Theme.sm : Theme.md)
    case .bullet(let value):
      HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
        Circle().fill(Theme.accent).frame(width: 5, height: 5)
        inlineText(value)
          .font(.body)
          .foregroundStyle(Theme.ink)
      }
    case .quote(let value):
      HStack(alignment: .top, spacing: Theme.md) {
        RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3)
        inlineText(value)
          .font(.callout.italic())
          .foregroundStyle(Theme.inkSoft)
      }
      .padding(.vertical, Theme.xs)
    case .code(let value):
      Text(value)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(Theme.ink)
        .padding(Theme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
    case .paragraph(let value):
      inlineText(value)
        .font(.body)
        .foregroundStyle(Theme.inkSoft)
        .lineSpacing(3)
    case .space:
      Color.clear.frame(height: 1)
    }
  }

  private func inlineText(_ value: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: value, options: options) {
      return Text(attributed)
    }
    return Text(value)
  }

  private var blocks: [Block] {
    var result: [Block] = []
    var inCode = false
    var codeLines: [String] = []
    for line in markdown.components(separatedBy: .newlines) {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        if inCode {
          result.append(.code(codeLines.joined(separator: "\n")))
          codeLines.removeAll()
        }
        inCode.toggle()
      } else if inCode {
        codeLines.append(line)
      } else if line.hasPrefix("### ") {
        result.append(.heading(2, String(line.dropFirst(4))))
      } else if line.hasPrefix("## ") {
        result.append(.heading(2, String(line.dropFirst(3))))
      } else if line.hasPrefix("# ") {
        result.append(.heading(1, String(line.dropFirst(2))))
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
        result.append(.bullet(String(line.dropFirst(2))))
      } else if line.hasPrefix("> ") {
        result.append(.quote(String(line.dropFirst(2))))
      } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
        result.append(.space)
      } else {
        result.append(.paragraph(line))
      }
    }
    if !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
    return result
  }

  private enum Block {
    case heading(Int, String)
    case bullet(String)
    case quote(String)
    case code(String)
    case paragraph(String)
    case space
  }
}

/// A book-first summary sheet used by the Notes tab. It deliberately exposes
/// every detected source chapter at once: a heading and two-sentence recap are
/// quicker to scan than the former long-form guide sections.
struct BookSummaryListView: View {
  @Bindable var book: Book
  let initialOffset: Int
  @Environment(\.dismiss) private var dismiss

  private var sections: [ChapterSummarySection] { ChapterSummaryContent.sections(for: book) }
  private var activeSectionID: String? {
    ChapterSummaryContent.section(for: book, offset: initialOffset)?.id
  }

  var body: some View {
    NavigationStack {
      Group {
        if sections.isEmpty {
          ContentUnavailableView {
            Label("No chapter text", systemImage: "doc.text.magnifyingglass")
          } description: {
            Text("Inkflow needs extractable chapter text to create summaries.")
          }
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.md) {
              VStack(alignment: .leading, spacing: Theme.xs) {
                Text("\(sections.count) DETECTED \(sections.count == 1 ? "CHAPTER" : "CHAPTERS")")
                  .font(.caption.weight(.bold))
                  .tracking(1)
                  .foregroundStyle(Theme.inkFaint)
                Text("A short return to every chapter.")
                  .font(.title3.weight(.bold))
                  .foregroundStyle(Theme.ink)
              }
              .padding(.bottom, Theme.xs)

              ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                VStack(alignment: .leading, spacing: Theme.md) {
                  HStack {
                    Text("CHAPTER \(index + 1)")
                      .font(.system(size: 10, weight: .bold))
                      .tracking(1)
                      .foregroundStyle(section.id == activeSectionID ? Theme.accent : Theme.inkFaint)
                    Spacer()
                    if section.id == activeSectionID {
                      Text("CURRENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    }
                  }
                  ChapterSummaryMarkdownView(markdown: ChapterSummaryContent.markdown(for: section))
                }
                .padding(Theme.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(section.id == activeSectionID ? Theme.accent.opacity(0.4) : Theme.hairline)
                }
              }
            }
            .padding(Theme.lg)
          }
        }
      }
      .background(Theme.paper)
      .navigationTitle(book.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .tint(Theme.accent)
        }
      }
    }
  }
}

/// Per-book chapter workspace shared by the reader, audiobook player and the
/// Notebook tab. A deterministic grounded preview works offline; the reader can
/// explicitly refresh a chapter with AI while preserving the same concise form.
struct ChapterSummaryView: View {
  @Bindable var book: Book
  let initialOffset: Int
  var initialTab: Tab = .summary

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var selectedChapterID = ""
  @State private var selectedTab: Tab
  @State private var thoughtDraft = ""
  @State private var previewThought = false
  @State private var didSave = false
  @State private var aiMarkdown: String?
  @State private var aiError: String?
  @State private var isGeneratingAI = false
  @FocusState private var thoughtFocused: Bool

  enum Tab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case thoughts = "My thoughts"
    var id: String { rawValue }
  }

  init(book: Book, initialOffset: Int, initialTab: Tab = .summary) {
    self.book = book
    self.initialOffset = initialOffset
    self.initialTab = initialTab
    _selectedTab = State(initialValue: initialTab)
  }

  private var sections: [ChapterSummarySection] { ChapterSummaryContent.sections(for: book) }

  private var selectedSection: ChapterSummarySection? {
    sections.first { $0.id == selectedChapterID }
      ?? ChapterSummaryContent.section(for: book, offset: initialOffset)
      ?? sections.first
  }

  var body: some View {
    NavigationStack {
      Group {
        if let section = selectedSection {
          ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
              chapterPicker(section)

              Picker("Chapter workspace", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
              }
              .pickerStyle(.segmented)

              if selectedTab == .summary {
                summaryContent(section)
              } else {
                thoughtsContent(section)
              }
            }
            .padding(Theme.lg)
          }
        } else {
          ContentUnavailableView {
            Label("No chapter text", systemImage: "doc.text.magnifyingglass")
          } description: {
            Text("Inkflow needs extractable text to create a chapter summary.")
          }
        }
      }
      .background(Theme.paper)
      .navigationTitle("Chapter summary")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear(perform: configureInitialChapter)
      .onChange(of: selectedChapterID) { _, _ in
        loadThought()
        resetAISummary()
      }
      .onChange(of: selectedTab) { _, newValue in
        if newValue == .thoughts { loadThought() }
      }
    }
  }

  private func chapterPicker(_ section: ChapterSummarySection) -> some View {
    Menu {
      Picker("Chapter", selection: $selectedChapterID) {
        ForEach(sections) { item in
          Text(item.title).tag(item.id)
        }
      }
    } label: {
      HStack(spacing: Theme.md) {
        VStack(alignment: .leading, spacing: 3) {
          Text(book.title)
            .font(.caption)
            .foregroundStyle(Theme.inkFaint)
            .lineLimit(1)
          Text(section.title)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
        }
        Spacer()
        Text("\((sections.firstIndex(of: section) ?? 0) + 1) of \(sections.count)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Theme.inkSoft)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption.weight(.bold))
          .foregroundStyle(Theme.accent)
      }
      .padding(Theme.md)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline))
    }
    .buttonStyle(.plain)
  }

  private func summaryContent(_ section: ChapterSummarySection) -> some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      ChapterSummaryMarkdownView(
        markdown: ChapterSummaryContent.markdown(for: section, generatedText: aiMarkdown)
      )
        .padding(Theme.lg)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline))

      VStack(alignment: .leading, spacing: Theme.md) {
        Button {
          generateAISummary(for: section)
        } label: {
          Label(
            isGeneratingAI ? "Writing summary…" : "Refresh with AI",
            systemImage: isGeneratingAI ? "hourglass" : "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(isGeneratingAI)

        HStack(spacing: Theme.md) {
          Button {
            selectedTab = .thoughts
            thoughtFocused = true
          } label: {
            Label("Add your thoughts", systemImage: "square.and.pencil")
          }
          .buttonStyle(.bordered)
          .tint(Theme.accent)

          if book.format == .text {
            Button {
              // Chapter selection is intentional backwards-capable reader
              // navigation, unlike a stale mode-dismissal checkpoint.
              book.updateCharacterOffset(section.startOffset, allowingBackward: true)
              try? context.save()
              dismiss()
            } label: {
              Label("Read chapter", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
          }
        }
      }

      if isGeneratingAI {
        ProgressView("Writing two short sentences…")
          .font(.caption)
          .tint(Theme.accent)
      }

      if let aiError {
        Text(aiError)
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
      }

      Text("AI uses only this chapter's text. Your local two-sentence summary is always available offline.")
      .font(.caption)
      .foregroundStyle(Theme.inkFaint)
    }
  }

  private func thoughtsContent(_ section: ChapterSummarySection) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Make it yours")
            .font(.headline)
            .foregroundStyle(Theme.ink)
          Text("Markdown is supported")
            .font(.caption)
            .foregroundStyle(Theme.inkFaint)
        }
        Spacer()
        Button(previewThought ? "Edit" : "Preview") {
          withAnimation(.snappy) {
            previewThought.toggle()
            thoughtFocused = !previewThought
          }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .disabled(thoughtDraft.isEmpty && !previewThought)
      }

      if previewThought {
        ChapterSummaryMarkdownView(
          markdown: thoughtDraft.isEmpty ? "*Nothing written yet.*" : thoughtDraft
        )
        .padding(Theme.lg)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline))
      } else {
        TextEditor(text: $thoughtDraft)
          .focused($thoughtFocused)
          .font(.body)
          .foregroundStyle(Theme.ink)
          .scrollContentBackground(.hidden)
          .padding(Theme.md)
          .frame(minHeight: 260)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
          .overlay(alignment: .topLeading) {
            if thoughtDraft.isEmpty {
              Text("## What stayed with me\n\n- A key idea\n- A question I still have\n\n> A passage worth remembering")
                .font(.body)
                .foregroundStyle(Theme.inkFaint.opacity(0.65))
                .padding(.horizontal, Theme.lg)
                .padding(.vertical, Theme.lg + 7)
                .allowsHitTesting(false)
            }
          }
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline))
      }

      Button(action: saveThought) {
        Label(didSave ? "Saved to Notebook" : "Save to Notebook", systemImage: didSave ? "checkmark" : "bookmark")
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(Theme.accent)
      .disabled(thoughtDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      Text("Your thoughts stay editable and are included in Notebook exports.")
        .font(.caption)
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .onChange(of: thoughtDraft) { _, _ in didSave = false }
  }

  private func configureInitialChapter() {
    guard selectedChapterID.isEmpty else { return }
    selectedChapterID =
      ChapterSummaryContent.section(for: book, offset: initialOffset)?.id
      ?? sections.first?.id ?? ""
    loadThought()
  }

  private func thoughtNote(for section: ChapterSummarySection) -> Note? {
    book.notes.first {
      $0.chapterTitle == section.title && $0.startOffset == section.startOffset
        && $0.passage == "My chapter thoughts"
    }
  }

  private func loadThought() {
    guard let section = selectedSection else { return }
    thoughtDraft = thoughtNote(for: section)?.body ?? ""
    previewThought = false
    didSave = false
  }

  private func saveThought() {
    guard let section = selectedSection else { return }
    let body = thoughtDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if let existing = thoughtNote(for: section) {
      existing.body = body
    } else {
      context.insert(
        Note(
          passage: "My chapter thoughts", body: body, chapterTitle: section.title,
          startOffset: section.startOffset, book: book))
    }
    try? context.save()
    didSave = true
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func resetAISummary() {
    aiMarkdown = nil
    aiError = nil
    isGeneratingAI = false
  }

  private func generateAISummary(for section: ChapterSummarySection) {
    guard !isGeneratingAI else { return }
    isGeneratingAI = true
    aiError = nil
    Task {
      do {
        let result = try await AISummaryService.generate(
          book: book, sectionTitle: section.title, text: section.text)
        await MainActor.run {
          aiMarkdown = result.markdown
          isGeneratingAI = false
        }
      } catch {
        await MainActor.run {
          aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          isGeneratingAI = false
        }
      }
    }
  }
}

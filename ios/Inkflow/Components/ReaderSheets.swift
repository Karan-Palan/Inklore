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
  /// Chapter extraction can parse an entire EPUB spine and is requested by
  /// several SwiftUI views during one render pass. Cache a bounded handful of
  /// immutable imports so tab changes and animations do not reread every file.
  private final class SectionCacheBox: NSObject {
    let sections: [ChapterSummarySection]
    init(_ sections: [ChapterSummarySection]) { self.sections = sections }
  }

  private final class MarkdownCacheBox: NSObject {
    let markdown: String
    init(_ markdown: String) { self.markdown = markdown }
  }

  private static let sectionCache: NSCache<NSString, SectionCacheBox> = {
    let cache = NSCache<NSString, SectionCacheBox>()
    cache.countLimit = 8
    cache.totalCostLimit = 24 * 1_024 * 1_024
    return cache
  }()

  private static let markdownCache: NSCache<NSString, MarkdownCacheBox> = {
    let cache = NSCache<NSString, MarkdownCacheBox>()
    cache.countLimit = 160
    return cache
  }()

  static func sections(for book: Book) -> [ChapterSummarySection] {
    let cacheKey = NSString(
      string: "\(book.id.uuidString):\(book.formatRaw):\(book.epubFolderName):\(book.storedText.utf16.count):\(book.chapters.count)")
    if let cached = sectionCache.object(forKey: cacheKey) { return cached.sections }

    let extracted = uncachedSections(for: book)
    let cost = extracted.reduce(0) { $0 + $1.text.utf16.count * 2 }
    sectionCache.setObject(SectionCacheBox(extracted), forKey: cacheKey, cost: cost)
    return extracted
  }

  private static func uncachedSections(for book: Book) -> [ChapterSummarySection] {
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
    let key = NSString(string: "\(section.id):\(section.text.utf16.count)")
    if let cached = markdownCache.object(forKey: key) { return cached.markdown }
    let source = summaryBody(in: section.text, chapterTitle: section.title)
    let rendered = conciseMarkdown(title: section.title, source: source, fallback: source)
    markdownCache.setObject(MarkdownCacheBox(rendered), forKey: key)
    return rendered
  }

  /// The short brief is kept separate from its Markdown presentation so the
  /// chapter workspace can give it visual priority without reparsing a heading.
  static func brief(for section: ChapterSummarySection, generatedText: String? = nil) -> [String] {
    let generated = generatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let source = generated.isEmpty ? section.text : generated
    return briefSentences(
      source: summaryBody(in: source, chapterTitle: section.title),
      fallback: summaryBody(in: section.text, chapterTitle: section.title))
  }

  /// Source-grounded supporting ideas for the chapter workspace. These are not
  /// generated claims: they are useful sentences from the imported chapter.
  static func keyIdeas(for section: ChapterSummarySection) -> [String] {
    let source = summaryBody(in: section.text, chapterTitle: section.title)
    let sentences = sentenceList(from: source).filter(isUsefulSentence)
    let brief = Set(brief(for: section))
    let keywords = frequentTerms(in: source)
    let ideas = sentences.enumerated()
      .filter { !brief.contains($0.element) }
      .sorted {
        sentenceScore($0.element, keywords: keywords, position: $0.offset)
          > sentenceScore($1.element, keywords: keywords, position: $1.offset)
      }
      .prefix(3)
      .map(\.element)
    return ideas.isEmpty ? Array(brief) : ideas
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
        !trimmed.hasPrefix("#"),
        !isBoilerplate(withoutMarkdown)
      else { return nil }
      return withoutMarkdown
    }
    return keptLines.joined(separator: " ")
  }

  private static func conciseMarkdown(title: String, source: String, fallback: String) -> String {
    "# \(title)\n\n\(briefSentences(source: source, fallback: fallback).joined(separator: "\n\n"))"
  }

  private static func briefSentences(source: String, fallback: String) -> [String] {
    var sentences = sentenceList(from: source)
    if sentences.count < 2 {
      sentences += sentenceList(from: fallback).filter { candidate in
        !sentences.contains(candidate)
      }
    }
    if sentences.isEmpty {
      return [
        "No extractable text was found for this chapter yet.",
        "Try re-importing the source with text recognition enabled.",
      ]
    }
    if sentences.count == 1 {
      return [sentences[0], "The available text is brief, so this summary stays close to the chapter's opening idea."]
    }
    return selectTwoSentences(from: sentences)
  }

  private static func selectTwoSentences(from sentences: [String]) -> [String] {
    let useful = sentences.filter(isUsefulSentence)
    guard !useful.isEmpty else { return [] }
    let keywords = frequentTerms(in: useful.joined(separator: " "))
    let ranked = useful.enumerated().sorted { lhs, rhs in
      sentenceScore(lhs.element, keywords: keywords, position: lhs.offset)
        > sentenceScore(rhs.element, keywords: keywords, position: rhs.offset)
    }
    let winners = Array(ranked.prefix(2)).sorted { $0.offset < $1.offset }.map(\.element)
    return winners.count == 1 ? [winners[0], winners[0]] : winners
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
      if value.count >= 12, value.count <= 300, !isBoilerplate(value) {
        result.append(value)
      }
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
    // Position is only a tie-breaker. The previous large opening bonus caused
    // tables of contents and publisher notices to beat the actual chapter.
    let openingBonus = position == 0 ? 0.35 : 0
    return Double(hits) + openingBonus - Double(sentence.count) / 1_000
  }

  private static func isUsefulSentence(_ sentence: String) -> Bool {
    guard !isBoilerplate(sentence) else { return false }
    let words = sentence.split { !$0.isLetter && !$0.isNumber }
    return words.count >= 6
  }

  /// Imported PDFs commonly prepend a table of contents and append publishing
  /// notices to a detected chapter. Those are valid source text but never a
  /// useful two-line recap, so remove them before ranking—not after rendering.
  private static func isBoilerplate(_ text: String) -> Bool {
    let lower = text.lowercased()
    let blockedPhrases = [
      "all rights reserved", "copyright", "cover design", "cover copyright",
      "published by", "publishing group", "trademark", "newsletter", "isbn",
      "library of congress", "www.", "http://", "https://",
    ]
    if blockedPhrases.contains(where: lower.contains) { return true }
    let ruleMarkers = lower.components(separatedBy: "rule #").count - 1
    if ruleMarkers >= 2 { return true }
    return false
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
    case .ordered(let marker, let value):
      HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
        Text(marker)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.accent)
          .frame(minWidth: 18, alignment: .trailing)
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
    var paragraphLines: [String] = []
    var quoteLines: [String] = []

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      result.append(.paragraph(paragraphLines.joined(separator: " ")))
      paragraphLines.removeAll()
    }

    func flushQuote() {
      guard !quoteLines.isEmpty else { return }
      result.append(.quote(quoteLines.joined(separator: " ")))
      quoteLines.removeAll()
    }

    for line in markdown.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        flushParagraph()
        flushQuote()
        if inCode {
          result.append(.code(codeLines.joined(separator: "\n")))
          codeLines.removeAll()
        }
        inCode.toggle()
      } else if inCode {
        codeLines.append(line)
      } else if line.hasPrefix("### ") {
        flushParagraph()
        flushQuote()
        result.append(.heading(2, String(line.dropFirst(4))))
      } else if line.hasPrefix("## ") {
        flushParagraph()
        flushQuote()
        result.append(.heading(2, String(line.dropFirst(3))))
      } else if line.hasPrefix("# ") {
        flushParagraph()
        flushQuote()
        result.append(.heading(1, String(line.dropFirst(2))))
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
        flushParagraph()
        flushQuote()
        result.append(.bullet(String(line.dropFirst(2))))
      } else if line.hasPrefix("> ") {
        flushParagraph()
        quoteLines.append(String(line.dropFirst(2)))
      } else if let ordered = orderedItem(in: trimmed) {
        flushParagraph()
        flushQuote()
        result.append(.ordered(ordered.marker, ordered.value))
      } else if trimmed.isEmpty {
        flushParagraph()
        flushQuote()
        if result.last != .space { result.append(.space) }
      } else {
        flushQuote()
        paragraphLines.append(trimmed)
      }
    }
    flushParagraph()
    flushQuote()
    if !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
    return result
  }

  private func orderedItem(in line: String) -> (marker: String, value: String)? {
    guard let dot = line.firstIndex(of: ".") else { return nil }
    let number = line[..<dot]
    let afterDot = line.index(after: dot)
    guard !number.isEmpty, number.allSatisfy(\.isNumber),
      afterDot < line.endIndex, line[afterDot] == " "
    else { return nil }
    return ("\(number).", String(line[line.index(after: afterDot)...]))
  }

  private enum Block: Equatable {
    case heading(Int, String)
    case bullet(String)
    case ordered(String, String)
    case quote(String)
    case code(String)
    case paragraph(String)
    case space
  }
}

/// The book layer of the notebook summary hierarchy. A book first opens to a
/// calm chapter index; selecting a chapter opens its focused workspace.
struct BookSummaryListView: View {
  @Bindable var book: Book
  let initialOffset: Int
  @Environment(\.dismiss) private var dismiss
  @State private var selectedSection: ChapterSummarySection?

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
            LazyVStack(alignment: .leading, spacing: Theme.sm) {
              HStack(alignment: .top, spacing: Theme.md) {
                BookCover(book: book, width: 54, showAudioBadge: false)
                VStack(alignment: .leading, spacing: 3) {
                  Text(book.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                  Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                  Text("\(sections.count) \(sections.count == 1 ? "chapter" : "chapters") · two-minute return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, Theme.xs)
                }
              }
              .padding(.bottom, Theme.md)

              Text("CHAPTERS")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)

              ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                Button { selectedSection = section } label: {
                  HStack(alignment: .top, spacing: Theme.md) {
                    Text("\(index + 1)")
                      .font(.subheadline.weight(.bold))
                      .foregroundStyle(section.id == activeSectionID ? Theme.accent : Theme.inkFaint)
                      .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                      Text(section.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                      Text(ChapterSummaryContent.brief(for: section).joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                    }
                    Spacer(minLength: Theme.xs)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.bold))
                      .foregroundStyle(Theme.inkFaint)
                      .padding(.top, 4)
                  }
                  .padding(.vertical, Theme.md)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(alignment: .bottom) {
                  if index < sections.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 1) }
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
    .sheet(item: $selectedSection) { section in
      ChapterSummaryView(book: book, initialOffset: section.startOffset, initialSectionID: section.id)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

/// Per-book chapter workspace shared by the reader, audiobook player and the
/// Notebook tab. A deterministic grounded preview works offline; the reader can
/// explicitly refresh a chapter with AI while preserving the same concise form.
struct ChapterSummaryView: View {
  @Bindable var book: Book
  let initialOffset: Int
  let initialSectionID: String?
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
    case summary = "Chapter"
    case thoughts = "My Thoughts"
    var id: String { rawValue }
  }

  init(
    book: Book,
    initialOffset: Int,
    initialSectionID: String? = nil,
    initialTab: Tab = .summary
  ) {
    self.book = book
    self.initialOffset = initialOffset
    self.initialSectionID = initialSectionID
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
      .navigationTitle("Chapter workspace")
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
      .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func summaryContent(_ section: ChapterSummarySection) -> some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      briefPanel(for: section)
      keyIdeasPanel(for: section)
      highlightsPanel(for: section)

      Button(action: { jumpToChapter(section) }) {
        Label("Jump to chapter", systemImage: "arrow.right.circle.fill")
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(Theme.accent)

      HStack(spacing: Theme.lg) {
        Button {
          selectedTab = .thoughts
          thoughtFocused = true
        } label: {
          Label("My Thoughts", systemImage: "square.and.pencil")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)

        Button {
          generateAISummary(for: section)
        } label: {
          Label(isGeneratingAI ? "Writing brief…" : "Refresh brief", systemImage: "sparkles")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.inkSoft)
        .disabled(isGeneratingAI)
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

      Text("The brief is always two source-grounded sentences. AI only refreshes this chapter and never replaces your notes.")
      .font(.caption)
      .foregroundStyle(Theme.inkFaint)
    }
  }

  private func briefPanel(for section: ChapterSummarySection) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Text("BRIEF")
        .font(.caption.weight(.bold))
        .tracking(1)
        .foregroundStyle(Theme.accent)
      ForEach(ChapterSummaryContent.brief(for: section, generatedText: aiMarkdown), id: \.self) { sentence in
        Text(sentence)
          .font(.body)
          .foregroundStyle(Theme.ink)
          .lineSpacing(3)
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
  }

  private func keyIdeasPanel(for section: ChapterSummarySection) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Label("Key ideas", systemImage: "lightbulb")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      ForEach(ChapterSummaryContent.keyIdeas(for: section), id: \.self) { idea in
        HStack(alignment: .top, spacing: Theme.sm) {
          Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
          Text(idea)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .lineSpacing(2)
        }
      }
    }
    .padding(.vertical, Theme.sm)
  }

  private func highlightsPanel(for section: ChapterSummarySection) -> some View {
    let highlights = chapterHighlights(for: section)
    return VStack(alignment: .leading, spacing: Theme.md) {
      HStack {
        Label("Highlights", systemImage: "highlighter")
          .font(.headline)
          .foregroundStyle(Theme.ink)
        Spacer()
        if !highlights.isEmpty {
          Text("\(highlights.count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.inkFaint)
        }
      }
      if highlights.isEmpty {
        Text("Nothing highlighted here yet. Mark a passage while reading and it will appear here.")
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
      } else {
        ForEach(highlights) { highlight in
          Text(highlight.text)
            .font(.system(.subheadline, design: .serif).italic())
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(4)
            .padding(.leading, Theme.md)
            .overlay(alignment: .leading) {
              Capsule().fill(HighlightColor(rawValue: highlight.colorName)?.color ?? Theme.highlightYellow)
                .frame(width: 3)
            }
        }
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
  }

  private func chapterHighlights(for section: ChapterSummarySection) -> [Highlight] {
    book.highlights
      .filter { $0.startOffset >= section.startOffset && $0.startOffset < section.endOffset }
      .sorted { $0.createdDate > $1.createdDate }
  }

  private func jumpToChapter(_ section: ChapterSummarySection) {
    if book.isEpub, let index = sections.firstIndex(of: section) {
      _ = book.updateEpubPosition(
        spineIndex: index, scroll: 0, spineCount: sections.count,
        characterOffset: section.startOffset, allowingBackward: true)
    } else {
      _ = book.updateCharacterOffset(section.startOffset, allowingBackward: true)
    }
    try? context.save()
    dismiss()
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
        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
      } else {
        TextEditor(text: $thoughtDraft)
          .focused($thoughtFocused)
          .font(.body)
          .foregroundStyle(Theme.ink)
          .scrollContentBackground(.hidden)
          .padding(Theme.md)
          .frame(minHeight: 260)
          .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
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
      initialSectionID
      ?? ChapterSummaryContent.section(for: book, offset: initialOffset)?.id
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

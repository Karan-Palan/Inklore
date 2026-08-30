import Foundation
import SwiftData
import UIKit

/// Imports local files, public links, web articles, and pasted writing. Parsing
/// is local-first: user documents are never uploaded as part of import.
enum BookImporter {
  enum ImportError: LocalizedError {
    case unreadable, unsupported, badDownload, emptyText, tooLarge

    var errorDescription: String? {
      switch self {
      case .unreadable:
        return "We couldn't read that document. It may be damaged or password protected."
      case .unsupported:
        return "Inkflow supports PDF, EPUB, DOCX, RTF, Markdown, plain text, and web articles."
      case .badDownload:
        return "We couldn't download that link. Check that it is public and try again."
      case .emptyText:
        return "Add some text before importing."
      case .tooLarge:
        return "This file is too large to import safely on this device."
      }
    }
  }

  private enum Kind { case epub, pdf, docx, rtf, text, html }

  /// Link resolution is performed by the API for articles. Direct document
  /// links are validated there and then downloaded locally, preserving the
  /// native PDF/EPUB reader rather than proxying a book through the backend.
  private struct LinkResolution: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable { case article, file }

    let kind: Kind
    let title: String
    let author: String?
    let text: String?
    let sourceName: String
    let sourceURL: String
    let contentType: String?

    enum CodingKeys: String, CodingKey {
      case kind, title, author, text
      case sourceName = "source_name"
      case sourceURL = "source_url"
      case contentType = "content_type"
    }
  }

  private struct LinkRequest: Encodable, Sendable { let url: String }

  private static let maximumImportBytes = 80 * 1024 * 1024
  private static let maximumStoredTextLength = 2_000_000

  /// Immutable parsing output which can return from a utility task to the
  /// MainActor, where ModelContext ownership is preserved.
  private enum PreparedImport: Sendable {
    case epub(folder: String, title: String, author: String, narration: String, spineCount: Int)
    case pdf(
      fileName: String, pageCount: Int, title: String?, fallbackTitle: String, author: String?, text: String)
    case text(title: String, author: String, text: String, description: String, chapters: [Chapter])
  }

  @MainActor @discardableResult
  static func importFile(at url: URL, into context: ModelContext) async throws -> Book {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let data = try await Task.detached(priority: .utility) {
      try readData(from: url)
    }.value
    return try await make(
      from: data, suggestedTitle: url.deletingPathExtension().lastPathComponent,
      extensionHint: url.pathExtension, mimeHint: nil, sourceLabel: "Imported file",
      into: context)
  }

  @MainActor @discardableResult
  static func importRemote(from url: URL, into context: ModelContext) async throws -> Book {
    var request = URLRequest(url: url)
    request.timeoutInterval = 90
    request.setValue("Inkflow/1.0", forHTTPHeaderField: "User-Agent")
    let data: Data
    let response: URLResponse
    do {
      let temporaryURL: URL
      (temporaryURL, response) = try await URLSession.shared.download(for: request)
      guard response.expectedContentLength <= Int64(maximumImportBytes)
        || response.expectedContentLength < 0
      else { throw ImportError.tooLarge }
      data = try await Task.detached(priority: .utility) {
        try readData(from: temporaryURL)
      }.value
    } catch let error as ImportError {
      throw error
    } catch {
      throw ImportError.badDownload
    }
    guard let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode), !data.isEmpty
    else { throw ImportError.badDownload }

    let filename = response.suggestedFilename
    let responseTitle = filename.map { ($0 as NSString).deletingPathExtension }
    let responseExtension = filename.map { ($0 as NSString).pathExtension }
    let urlTitle = url.deletingPathExtension().lastPathComponent
    let host = url.host?.replacingOccurrences(of: "www.", with: "")
    let suggested = [responseTitle, urlTitle, host].compactMap { $0 }
      .first(where: { !$0.isEmpty }) ?? "Imported article"

    return try await make(
      from: data, suggestedTitle: suggested,
      extensionHint: responseExtension?.isEmpty == false ? responseExtension : url.pathExtension,
      mimeHint: response.mimeType, sourceLabel: host ?? "Web", into: context)
  }

  /// Imports an arbitrary public URL. The backend extracts ordinary articles
  /// (including public X status URLs) into clean text. Validated PDF/EPUB and
  /// other document URLs continue through the device-local import path.
  @MainActor @discardableResult
  static func importLink(from url: URL, into context: ModelContext) async throws -> Book {
    let resolution: LinkResolution
    do {
      resolution = try await BackendClient().send(
        LinkResolution.self,
        path: "/api/v1/link-import",
        body: LinkRequest(url: url.absoluteString))
    } catch {
      throw ImportError.badDownload
    }

    switch resolution.kind {
    case .file:
      guard let remoteURL = URL(string: resolution.sourceURL) else {
        throw ImportError.badDownload
      }
      return try await importRemote(from: remoteURL, into: context)

    case .article:
      guard let text = resolution.text,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { throw ImportError.emptyText }
      let prepared = try await Task.detached(priority: .utility) {
        try prepareText(
          title: cleanedTitle(resolution.title),
          author: nonBlank(resolution.author) ?? "Web",
          text: text,
          description: "Imported article from \(resolution.sourceName).")
      }.value
      return try persist(prepared, sourceLabel: resolution.sourceName, into: context)
    }
  }

  @MainActor @discardableResult
  static func importText(title: String, text: String, into context: ModelContext) async throws -> Book {
    let prepared = try await Task.detached(priority: .utility) {
      try prepareText(
        title: cleanedTitle(title), author: "My writing", text: text,
        description: "Text added in Inkflow.")
    }.value
    return try persist(prepared, sourceLabel: "Pasted text", into: context)
  }

  @MainActor
  private static func make(
    from data: Data, suggestedTitle: String, extensionHint: String?, mimeHint: String?,
    sourceLabel: String, into context: ModelContext
  ) async throws -> Book {
    let prepared = try await Task.detached(priority: .utility) {
      try prepare(
        from: data, suggestedTitle: suggestedTitle, extensionHint: extensionHint, mimeHint: mimeHint)
    }.value
    return try persist(prepared, sourceLabel: sourceLabel, into: context)
  }

  private static func prepare(
    from data: Data, suggestedTitle: String, extensionHint: String?, mimeHint: String?
  ) throws -> PreparedImport {
    guard let kind = detectKind(data, extensionHint: extensionHint, mimeHint: mimeHint) else {
      throw ImportError.unsupported
    }
    let fallbackTitle = cleanedTitle(suggestedTitle)

    switch kind {
    case .epub:
      let folder = try EpubArchive.extract(data)
      guard let document = EpubDocument(folderName: folder), !document.chapters.isEmpty else {
        EpubArchive.removeFolder(named: folder)
        throw ImportError.unreadable
      }
      return .epub(
        folder: folder, title: document.title.isEmpty ? fallbackTitle : document.title,
        author: document.author.isEmpty ? "Unknown author" : document.author,
        narration: document.plainText(), spineCount: document.chapters.count)

    case .pdf:
      let saved = try PdfStore.save(data)
      return .pdf(
        fileName: saved.fileName, pageCount: saved.pageCount, title: saved.title,
        fallbackTitle: fallbackTitle, author: saved.author, text: saved.text)

    case .docx:
      let parsed = try DocxDocument.parse(data)
      return try prepareText(
        title: nonBlank(parsed.title) ?? fallbackTitle,
        author: nonBlank(parsed.author) ?? "Unknown author", text: parsed.text,
        description: "Imported Word document.")

    case .rtf:
      guard let attributed = try? NSAttributedString(
        data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil)
      else { throw ImportError.unreadable }
      return try prepareText(
        title: fallbackTitle, author: "Unknown author", text: attributed.string,
        description: "Imported rich text document.")

    case .text:
      guard let text = decodedText(data) else { throw ImportError.unreadable }
      return try prepareText(
        title: fallbackTitle, author: "Unknown author", text: text,
        description: "Imported text document.")

    case .html:
      guard let html = decodedText(data) else { throw ImportError.unreadable }
      let article = webArticle(from: html)
      return try prepareText(
        title: nonBlank(article.title) ?? fallbackTitle,
        author: nonBlank(article.author) ?? "Web", text: article.text,
        description: "Imported web article.")
    }
  }

  @MainActor
  private static func persist(
    _ prepared: PreparedImport, sourceLabel: String, into context: ModelContext
  ) throws -> Book {
    let book: Book
    switch prepared {
    case let .epub(folder, title, author, narration, spineCount):
      let palette = coverPalette(for: title)
      book = Book(
        title: title, author: author, bookDescription: "Imported EPUB.", category: "Imported",
        coverHexStart: palette.0, coverHexEnd: palette.1, ratingTimesThousand: 0,
        storedText: narration, isDownloaded: true, sourceIdentifier: "import-" + UUID().uuidString,
        format: .epub, epubFolderName: folder, spineCount: spineCount, sourceName: sourceLabel)

    case let .pdf(fileName, pageCount, title, fallbackTitle, author, text):
      let resolvedTitle = nonBlank(title) ?? fallbackTitle
      let palette = coverPalette(for: resolvedTitle)
      book = Book(
        title: resolvedTitle, author: nonBlank(author) ?? "Unknown author",
        bookDescription: "Imported PDF.", category: "Imported", coverHexStart: palette.0,
        coverHexEnd: palette.1, totalPages: pageCount, ratingTimesThousand: 0, storedText: text,
        isDownloaded: true, sourceIdentifier: "import-" + UUID().uuidString, format: .pdf,
        pdfFileName: fileName, pdfPageCount: pageCount, sourceName: sourceLabel)

    case let .text(title, author, text, description, chapters):
      let palette = coverPalette(for: title)
      book = Book(
        title: title, author: author, bookDescription: description, category: "Imported",
        coverHexStart: palette.0, coverHexEnd: palette.1,
        totalPages: max(1, Int(ceil(Double((text as NSString).length) / 1_800))),
        ratingTimesThousand: 0, storedText: text, isDownloaded: true,
        sourceIdentifier: "import-" + UUID().uuidString, format: .text,
        sourceName: sourceLabel, chapters: chapters)
    }

    context.insert(book)
    do {
      try context.save()
    } catch {
      context.delete(book)
      if book.isEpub { EpubArchive.removeFolder(named: book.epubFolderName) }
      if book.isPdf { PdfStore.removeFile(named: book.pdfFileName) }
      throw error
    }
    return book
  }

  private static func prepareText(
    title: String, author: String, text: String, description: String
  ) throws -> PreparedImport {
    let clean = normalizedText(text)
    guard !clean.isEmpty else { throw ImportError.emptyText }
    let bounded: String
    let ns = clean as NSString
    if ns.length > maximumStoredTextLength {
      bounded = ns.substring(to: maximumStoredTextLength)
    } else {
      bounded = clean
    }
    return .text(
      title: title, author: author, text: bounded, description: description, chapters: chapterize(bounded))
  }

  private static func detectKind(
    _ data: Data, extensionHint: String?, mimeHint: String?
  ) -> Kind? {
    let ext = extensionHint?.lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let mime = mimeHint?.lowercased() ?? ""
    let bytes = [UInt8](data.prefix(5))
    if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }
    if bytes.count >= 2, bytes[0] == 0x50, bytes[1] == 0x4B {
      // ZIP entry names are stored plainly in the central directory. Checking
      // them directly avoids inflating an entire EPUB once merely to identify
      // it, then immediately expanding it again for import.
      if data.range(of: Data("META-INF/container.xml".utf8)) != nil { return .epub }
      if data.range(of: Data("word/document.xml".utf8)) != nil { return .docx }
      return nil
    }
    if String(decoding: data.prefix(5), as: UTF8.self).hasPrefix("{\\rtf") { return .rtf }
    if mime.contains("html") || ["html", "htm"].contains(ext ?? "") { return .html }
    if ["txt", "text", "md", "markdown", "csv"].contains(ext ?? "")
      || mime.hasPrefix("text/")
    { return .text }
    if ext == "rtf" { return .rtf }
    if decodedText(data) != nil { return .text }
    return nil
  }

  private static func decodedText(_ data: Data) -> String? {
    let encodings: [String.Encoding] = [
      .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1,
    ]
    for encoding in encodings {
      if let value = String(data: data, encoding: encoding),
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      { return value }
    }
    return nil
  }

  private static func webArticle(from html: String) -> (title: String?, author: String?, text: String) {
    let title = firstCapture("<title[^>]*>(.*?)</title>", in: html)
      .map { decodeEntities(stripTags($0)) }
    let author = firstCapture(
      "<meta[^>]+(?:name|property)=[\\\"'](?:author|article:author)[\\\"'][^>]+content=[\\\"']([^\\\"']+)",
      in: html)
    let preferred = firstCapture("<article[^>]*>(.*?)</article>", in: html) ?? html
    var body = preferred
    for tag in ["script", "style", "nav", "header", "footer", "aside", "svg", "noscript"] {
      body = body.replacingOccurrences(
        of: "<\(tag)[^>]*>.*?</\(tag)>", with: " ",
        options: [.regularExpression, .caseInsensitive])
    }
    body = body.replacingOccurrences(
      of: "</(p|div|h[1-6]|li|blockquote|section|tr)>", with: "\n\n",
      options: [.regularExpression, .caseInsensitive])
    body = body.replacingOccurrences(
      of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
    return (title, author, normalizedText(decodeEntities(stripTags(body))))
  }

  private static func chapterize(_ text: String) -> [Chapter] {
    let lines = text.components(separatedBy: .newlines)
    var result: [Chapter] = []
    var title = "Document"
    var paragraphs: [String] = []

    func flush() {
      guard !paragraphs.isEmpty else { return }
      result.append(Chapter(title: title, paragraphs: paragraphs))
      paragraphs.removeAll(keepingCapacity: true)
    }

    for raw in lines {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      let isHeading = line.range(
        of: "^(#{1,6}\\s+.+|chapter\\s+([0-9ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)(?:[\\s:.-].*)?|part\\s+([0-9ivxlcdm]+|one|two|three|four|five).*)$",
        options: [.regularExpression, .caseInsensitive]) != nil
      if isHeading {
        flush()
        title = line.replacingOccurrences(
          of: "^#{1,6}\\s+", with: "", options: .regularExpression)
      } else {
        paragraphs.append(line)
      }
    }
    flush()
    return result.isEmpty ? [Chapter(title: title, paragraphs: [text])] : result
  }

  private static func normalizedText(_ text: String) -> String {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
      .map {
        $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespaces)
      }
    return lines.joined(separator: "\n")
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripTags(_ value: String) -> String {
    value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
  }

  private static func decodeEntities(_ value: String) -> String {
    var result = value
    let entities = [
      "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
      "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
      "&ldquo;": "“", "&rdquo;": "”", "&hellip;": "…",
    ]
    for (entity, replacement) in entities {
      result = result.replacingOccurrences(of: entity, with: replacement)
    }
    return result
  }

  private static func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(
      pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func nonBlank(_ value: String?) -> String? {
    guard let value else { return nil }
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }

  private static func readData(from url: URL) throws -> Data {
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard let size = values.fileSize, size <= maximumImportBytes else {
        throw ImportError.tooLarge
      }
      return try Data(contentsOf: url, options: .mappedIfSafe)
    } catch let error as ImportError {
      throw error
    } catch {
      throw ImportError.unreadable
    }
  }

  private static func cleanedTitle(_ raw: String) -> String {
    let trimmed = raw.replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Imported Book" : trimmed
  }

  private static func coverPalette(for id: String) -> (UInt, UInt) {
    let palettes: [(UInt, UInt)] = [
      (0x2E3A59, 0x6C7A9C), (0x0F5C5B, 0x2FA39C), (0x7A1F3D, 0xC2703D),
      (0x4A3B2A, 0xB08545), (0x1F4F6E, 0x57A0C2), (0x37314A, 0x8A7BB0),
    ]
    return palettes[Int(id.hashValue.magnitude % UInt(palettes.count))]
  }
}

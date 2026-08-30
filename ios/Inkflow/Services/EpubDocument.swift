import Foundation

/// Reads an extracted EPUB folder and exposes its reading order (spine) as a
/// list of chapter file URLs, plus the table of contents. Uses `XMLParser` to
/// read `META-INF/container.xml` and the OPF package document.
struct EpubDocument {

  /// EPUB rendering uses the original files; this limit only bounds the
  /// flattened copy retained for TTS and SwiftData persistence.
  private static let maximumNarrationLength = 2_000_000

  struct Chapter: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL
  }

  let title: String
  let author: String
  /// Ordered chapter documents to render, one WKWebView load each.
  let chapters: [Chapter]
  /// Folder containing the OPF — the base for resolving relative hrefs/images.
  let baseURL: URL

  /// Builds a document from an extracted folder name. Returns nil if it can't
  /// locate a valid OPF/spine.
  init?(folderName: String) {
    let root = EpubArchive.folderURL(named: folderName)

    // 1. Find the OPF path from container.xml.
    let containerURL = root.appendingPathComponent("META-INF/container.xml")
    guard let containerData = try? Data(contentsOf: containerURL),
      let opfRelPath = Self.opfPath(from: containerData)
    else { return nil }

    let opfURL = root.appendingPathComponent(opfRelPath)
    let opfBase = opfURL.deletingLastPathComponent()
    guard let opfData = try? Data(contentsOf: opfURL) else { return nil }

    let parsed = OPFParser.parse(opfData)
    guard !parsed.spine.isEmpty else { return nil }

    // A spine gives us the real reading boundaries. When the EPUB includes an
    // NCX or EPUB3 navigation document, layer those human-authored labels onto
    // the same spine instead of guessing chapter headings from flattened text.
    let tocTitles = Self.tocTitles(for: parsed, opfBase: opfBase)

    // 2. Map spine idrefs → manifest hrefs → file URLs.
    var chapters: [Chapter] = []
    for idref in parsed.spine {
      guard let item = parsed.manifest[idref] else { continue }
      let href = item.href
      let decoded = href.removingPercentEncoding ?? href
      let fileURL = opfBase.appendingPathComponent(decoded)
      guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
      let title =
        tocTitles[Self.relativePath(of: fileURL, from: opfBase)]
        ?? Self.documentHeading(at: fileURL)
        ?? "Chapter \(chapters.count + 1)"
      chapters.append(Chapter(title: title, url: fileURL))
    }
    guard !chapters.isEmpty else { return nil }

    self.title = parsed.title
    self.author = parsed.author
    self.baseURL = opfBase
    self.chapters = chapters
  }

  /// Extracts flat, reflowable narration text from every spine chapter by
  /// stripping HTML tags. Used so EPUB books can be narrated via on-device TTS.
  func plainText() -> String {
    var parts: [String] = []
    var remaining = Self.maximumNarrationLength
    for chapter in chapters {
      guard remaining > 0 else { break }
      let text = text(for: chapter)
      guard !text.isEmpty else { continue }
      let ns = text as NSString
      if ns.length <= remaining {
        parts.append(text)
        remaining -= ns.length
      } else {
        parts.append(ns.substring(to: remaining))
        remaining = 0
      }
    }
    return parts.joined(separator: "\n\n")
  }

  /// Convenience: build a document for `folderName` and return its narration text.
  static func narrationText(folderName: String) -> String {
    EpubDocument(folderName: folderName)?.plainText() ?? ""
  }

  /// Extracted text for one real spine document. Summary discovery uses this
  /// rather than a flattened whole-book string so every EPUB summary respects
  /// the source publication's chapter boundary.
  func text(for chapter: Chapter) -> String {
    guard let data = try? Data(contentsOf: chapter.url) else { return "" }
    return Self.stripHTML(String(decoding: data, as: UTF8.self))
  }

  private static func relativePath(of url: URL, from baseURL: URL) -> String {
    let base = baseURL.standardizedFileURL.path.hasSuffix("/")
      ? baseURL.standardizedFileURL.path
      : baseURL.standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    return (relative.removingPercentEncoding ?? relative)
      .replacingOccurrences(of: "\\", with: "/")
  }

  private static func documentHeading(at url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let html = String(decoding: data, as: UTF8.self)
    let pattern = #"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
      match.numberOfRanges > 1
    else { return nil }
    let raw = (html as NSString).substring(with: match.range(at: 1))
    let heading = stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    return heading.isEmpty ? nil : heading
  }

  private static func tocTitles(for parsed: OPFParser.Result, opfBase: URL) -> [String: String] {
    let tocItem =
      parsed.tocID.flatMap { parsed.manifest[$0] }
      ?? parsed.manifest.values.first(where: { $0.mediaType.contains("ncx") })
      ?? parsed.manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") })
    guard let tocItem else { return [:] }
    let tocURL = opfBase.appendingPathComponent(tocItem.href.removingPercentEncoding ?? tocItem.href)
    guard let data = try? Data(contentsOf: tocURL) else { return [:] }
    let rawTitles = tocItem.mediaType.contains("ncx")
      ? NCXTOCParser.parse(data)
      : XHTMLTOCParser.parse(data)
    var titles: [String: String] = [:]
    for (href, title) in rawTitles {
      let pathOnly = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
      let targetURL = tocURL.deletingLastPathComponent().appendingPathComponent(
        pathOnly.removingPercentEncoding ?? pathOnly)
      let key = relativePath(of: targetURL, from: opfBase)
      if !key.isEmpty, !title.isEmpty { titles[key] = title }
    }
    return titles
  }

  /// Crude but effective HTML → text: drop script/style blocks, convert block
  /// tags to paragraph breaks, strip remaining tags, decode common entities.
  private static func stripHTML(_ html: String) -> String {
    var s = html
    // Remove script/style/head content.
    for tag in ["script", "style", "head"] {
      s = s.replacingOccurrences(
        of: "<\(tag)[^>]*>.*?</\(tag)>", with: " ",
        options: [.regularExpression, .caseInsensitive])
    }
    // Block-level closers → paragraph breaks.
    s = s.replacingOccurrences(
      of: "</(p|div|h[1-6]|li|br|tr)>", with: "\n\n",
      options: [.regularExpression, .caseInsensitive])
    s = s.replacingOccurrences(
      of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
    // Strip all remaining tags.
    s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    // Decode a few common entities.
    let entities = [
      "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
      "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
      "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
      "&hellip;": "…",
    ]
    for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
    // Collapse whitespace, keep paragraph breaks.
    let lines = s.components(separatedBy: "\n").map {
      $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    }
    var paragraphs: [String] = []
    var current = ""
    for line in lines {
      if line.isEmpty {
        if !current.isEmpty {
          paragraphs.append(current)
          current = ""
        }
      } else {
        current += current.isEmpty ? line : " " + line
      }
    }
    if !current.isEmpty { paragraphs.append(current) }
    return paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: container.xml

  private static func opfPath(from data: Data) -> String? {
    final class Handler: NSObject, XMLParserDelegate {
      var path: String?
      func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes attrs: [String: String]
      ) {
        if name == "rootfile", let p = attrs["full-path"], path == nil { path = p }
      }
    }
    let parser = XMLParser(data: data)
    let handler = Handler()
    parser.delegate = handler
    parser.parse()
    return handler.path
  }
}

/// Parses an OPF package document into title/author, manifest (id → href) and
/// spine order (list of idrefs).
private enum OPFParser {
  struct ManifestItem {
    let href: String
    let mediaType: String
    let properties: String
  }

  struct Result {
    var title: String = "Untitled"
    var author: String = "Unknown author"
    var manifest: [String: ManifestItem] = [:]
    var spine: [String] = []
    var tocID: String?
  }

  static func parse(_ data: Data) -> Result {
    let handler = Handler()
    let parser = XMLParser(data: data)
    parser.delegate = handler
    parser.parse()
    return handler.result
  }

  private final class Handler: NSObject, XMLParserDelegate {
    var result = Result()
    private var current = ""
    private var capturingTitle = false
    private var capturingAuthor = false

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes attrs: [String: String]
    ) {
      let tag = name.lowercased()
      switch tag {
      case "dc:title", "title":
        capturingTitle = true
        current = ""
      case "dc:creator", "creator":
        capturingAuthor = true
        current = ""
      case "item":
        if let id = attrs["id"], let href = attrs["href"] {
          result.manifest[id] = ManifestItem(
            href: href, mediaType: attrs["media-type"]?.lowercased() ?? "",
            properties: attrs["properties"]?.lowercased() ?? "")
        }
      case "spine":
        if let toc = attrs["toc"], !toc.isEmpty { result.tocID = toc }
      case "itemref":
        if let idref = attrs["idref"] {
          let linear = attrs["linear"]?.lowercased()
          if linear != "no" { result.spine.append(idref) }
        }
      default:
        break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if capturingTitle || capturingAuthor { current += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName: String?
    ) {
      let tag = name.lowercased()
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if tag == "dc:title" || tag == "title", capturingTitle {
        if !trimmed.isEmpty { result.title = trimmed }
        capturingTitle = false
      } else if tag == "dc:creator" || tag == "creator", capturingAuthor {
        if !trimmed.isEmpty { result.author = trimmed }
        capturingAuthor = false
      }
    }
  }
}

/// Extracts NCX navigation labels keyed by their content href. Keeping this
/// parser separate from OPF parsing lets us retain the spine as the source of
/// truth while still showing the publisher's table-of-contents labels.
private enum NCXTOCParser {
  static func parse(_ data: Data) -> [String: String] {
    let handler = Handler()
    let parser = XMLParser(data: data)
    parser.delegate = handler
    parser.parse()
    return handler.titles
  }

  private final class Handler: NSObject, XMLParserDelegate {
    private struct NavPoint {
      var href = ""
      var label = ""
    }

    var titles: [String: String] = [:]
    private var points: [NavPoint] = []
    private var isCapturingText = false

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes attrs: [String: String]
    ) {
      switch name.lowercased() {
      case "navpoint":
        points.append(NavPoint())
      case "content":
        if let src = attrs["src"], !points.isEmpty { points[points.count - 1].href = src }
      case "text":
        isCapturingText = !points.isEmpty
      default:
        break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard isCapturingText, !points.isEmpty else { return }
      points[points.count - 1].label += string
    }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName: String?
    ) {
      switch name.lowercased() {
      case "text":
        isCapturingText = false
      case "navpoint":
        guard let point = points.popLast() else { return }
        let label = point.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !point.href.isEmpty, !label.isEmpty { titles[point.href] = label }
      default:
        break
      }
    }
  }
}

/// EPUB3 navigation documents are XHTML. XMLParser handles well-formed EPUB
/// XHTML, and capturing anchors gives us the same href → label mapping as NCX.
private enum XHTMLTOCParser {
  static func parse(_ data: Data) -> [String: String] {
    let handler = Handler()
    let parser = XMLParser(data: data)
    parser.delegate = handler
    parser.parse()
    return handler.titles
  }

  private final class Handler: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:]
    private var href = ""
    private var label = ""
    private var isCapturingAnchor = false

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes attrs: [String: String]
    ) {
      guard name.lowercased() == "a", let value = attrs["href"] else { return }
      href = value
      label = ""
      isCapturingAnchor = true
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if isCapturingAnchor { label += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName: String?
    ) {
      guard name.lowercased() == "a", isCapturingAnchor else { return }
      let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
      if !href.isEmpty, !value.isEmpty { titles[href] = value }
      href = ""
      label = ""
      isCapturingAnchor = false
    }
  }
}

import Foundation

/// Talks to the public Internet Archive APIs to search real, freely-readable
/// books and download their plain-text edition into the local library.
///
/// - Search:    https://archive.org/advancedsearch.php (JSON)
/// - Text file: https://archive.org/download/<identifier>/<identifier>_djvu.txt
///
/// No API key is required. Results are limited to the `texts` mediatype.
enum InternetArchiveService {

  /// Archive's OCR text can be unexpectedly large. Bound the download and the
  /// SwiftData/TTS copy so a single result cannot exhaust device memory.
  private static let maximumDownloadBytes = 24 * 1024 * 1024
  private static let maximumStoredTextLength = 2_000_000

  struct SearchResult: Identifiable, Hashable {
    let identifier: String
    let title: String
    let author: String
    let year: String?
    let description: String
    /// Archive serves a generated cover thumbnail for every item.
    var coverURL: URL? {
      URL(string: "https://archive.org/services/img/\(identifier)")
    }

    var id: String { identifier }
  }

  enum ServiceError: LocalizedError {
    case badResponse
    case noText

    var errorDescription: String? {
      switch self {
      case .badResponse: return "Couldn't reach the Internet Archive. Check your connection."
      case .noText: return "This title has no readable text edition available."
      }
    }
  }

  // MARK: Search

  static func search(_ query: String, filters: SearchFilters = SearchFilters()) async throws
    -> [SearchResult]
  {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    // Build a relevance-focused query: weight the title/creator, require a
    // readable full-text edition, and drop the noisy collection/data items.
    let escaped = trimmed.replacingOccurrences(of: "\"", with: "")
    // Quote the phrase so the Archive matches the words together in the
    // title/creator rather than loosely OR-ing unrelated tokens.
    let phrase = "\"\(escaped)\""
    var clauses = [
      "(title:(\(phrase)) OR creator:(\(phrase)))",
      "mediatype:texts",
      // Require the DjVuTXT format specifically: that is the only edition we
      // can reliably download as plain text, so every result is openable.
      "format:(DjVuTXT)",
    ]
    if let lang = filters.language.archiveValue {
      clauses.append("language:(\(lang))")
    }
    let q = clauses.joined(separator: " AND ")

    let sortValue: String
    switch filters.sort {
    case .newest: sortValue = "year desc"
    case .title: sortValue = "titleSorter asc"
    case .popular: sortValue = "downloads desc"
    case .relevance: sortValue = ""
    }

    var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
    var items: [URLQueryItem] = [
      URLQueryItem(name: "q", value: q),
      URLQueryItem(name: "fl[]", value: "identifier"),
      URLQueryItem(name: "fl[]", value: "title"),
      URLQueryItem(name: "fl[]", value: "creator"),
      URLQueryItem(name: "fl[]", value: "year"),
      URLQueryItem(name: "fl[]", value: "description"),
      URLQueryItem(name: "rows", value: "40"),
      URLQueryItem(name: "page", value: "1"),
      URLQueryItem(name: "output", value: "json"),
    ]
    if !sortValue.isEmpty {
      items.append(URLQueryItem(name: "sort[]", value: sortValue))
    }
    components.queryItems = items

    guard let url = components.url else { throw ServiceError.badResponse }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20

    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ServiceError.badResponse
    }

    let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
    return decoded.response.docs.compactMap { doc in
      guard let id = doc.identifier, let title = doc.title?.value else { return nil }
      return SearchResult(
        identifier: id,
        title: title,
        author: doc.creator?.value ?? "Unknown author",
        year: doc.year?.value,
        description: doc.description?.value ?? ""
      )
    }
  }

  // MARK: Download text

  /// Downloads the plain-text edition and returns cleaned, reflowable body text.
  static func downloadText(for identifier: String) async throws -> String {
    // First try the conventional djvu filename, then fall back to whatever
    // text file the item actually exposes in its metadata file list.
    var candidates = [
      "https://archive.org/download/\(identifier)/\(identifier)_djvu.txt"
    ]
    if let discovered = try? await textFileURLs(for: identifier) {
      for u in discovered where !candidates.contains(u) {
        candidates.append(u)
      }
    }

    for urlString in candidates {
      try Task.checkCancellation()
      guard let url = URL(string: urlString) else { continue }
      var request = URLRequest(url: url)
      request.timeoutInterval = 60
      do {
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
        if response.expectedContentLength > Int64(maximumDownloadBytes) { continue }
        let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= maximumDownloadBytes,
          let data = try? Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        else { continue }
        let raw = String(decoding: data, as: UTF8.self)
        let cleaned = clean(raw)
        if cleaned.count > 400 { return cleaned }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        continue
      }
    }
    throw ServiceError.noText
  }

  /// Queries the item's metadata to find the real plain-text file name(s),
  /// since not every item follows the `<identifier>_djvu.txt` convention.
  private static func textFileURLs(for identifier: String) async throws -> [String] {
    guard let url = URL(string: "https://archive.org/metadata/\(identifier)") else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
    let meta = try JSONDecoder().decode(MetadataResponse.self, from: data)

    // Prefer DjVuTXT, then any .txt file, ranking larger files first.
    let txtFiles = meta.files.filter { file in
      guard let name = file.name else { return false }
      return name.lowercased().hasSuffix(".txt")
    }
    let ranked = txtFiles.sorted { a, b in
      let aDjvu = (a.format ?? "").localizedCaseInsensitiveContains("DjVuTXT")
      let bDjvu = (b.format ?? "").localizedCaseInsensitiveContains("DjVuTXT")
      if aDjvu != bDjvu { return aDjvu }
      return (Int(a.size ?? "0") ?? 0) > (Int(b.size ?? "0") ?? 0)
    }
    return ranked.compactMap { file in
      guard let name = file.name else { return nil }
      let encoded =
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
      return "https://archive.org/download/\(identifier)/\(encoded)"
    }
  }

  /// Lightweight cleanup of OCR'd djvu text: collapse hard-wrapped lines into
  /// paragraphs, drop page-number noise, normalize whitespace.
  private static func clean(_ raw: String) -> String {
    var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
    // Normalize 3+ newlines to a paragraph break marker.
    let lines = text.components(separatedBy: "\n")
    var paragraphs: [String] = []
    var current = ""
    var storedCharacters = 0

    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        if !current.isEmpty {
          let appended = append(current, to: &paragraphs, used: &storedCharacters)
          current = ""
          if !appended { break }
        }
        continue
      }
      // Skip standalone page-number lines.
      if line.count <= 4, Int(line) != nil { continue }
      if current.isEmpty {
        current = line
      } else {
        current += " " + line
      }
    }
    if !current.isEmpty { _ = append(current, to: &paragraphs, used: &storedCharacters) }

    text = paragraphs.joined(separator: "\n\n")
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Adds a paragraph without allowing OCR output to balloon the on-device
  /// database. Uses UTF-16 length because the reader and highlights do too.
  private static func append(_ paragraph: String, to parts: inout [String], used: inout Int) -> Bool {
    let available = maximumStoredTextLength - used
    guard available > 0 else { return false }
    let ns = paragraph as NSString
    if ns.length <= available {
      parts.append(paragraph)
      used += ns.length + 2
      return used < maximumStoredTextLength
    }
    parts.append(ns.substring(to: available))
    used = maximumStoredTextLength
    return false
  }

  // MARK: Decoding (IA returns inconsistent string/array fields)

  private struct SearchResponse: Decodable {
    let response: Inner
    struct Inner: Decodable { let docs: [Doc] }
  }

  private struct MetadataResponse: Decodable {
    let files: [MetaFile]
    struct MetaFile: Decodable {
      let name: String?
      let format: String?
      let size: String?
    }
  }

  private struct Doc: Decodable {
    let identifier: String?
    let title: FlexibleString?
    let creator: FlexibleString?
    let year: FlexibleString?
    let description: FlexibleString?
  }

  /// IA fields can be a String or an array of Strings. This flattens both.
  struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let s = try? container.decode(String.self) {
        value = s
      } else if let arr = try? container.decode([String].self) {
        value = arr.first ?? ""
      } else {
        value = ""
      }
    }
  }
}

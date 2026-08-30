import Foundation

/// Project Gutenberg, accessed through the public Gutendex API (https://gutendex.com).
/// Gutendex requires no API key and returns rich metadata plus direct download
/// URLs for real EPUB files (with embedded images/formatting) and covers.
/// This is the high-fidelity source: downloads are full EPUBs, not OCR text.
enum GutenbergService {

  struct Item: Identifiable, Hashable {
    let id: Int
    let title: String
    let author: String
    let epubURL: URL?
    let coverURL: URL?
    let subjects: [String]
  }

  enum ServiceError: LocalizedError {
    case badResponse
    case noEpub

    var errorDescription: String? {
      switch self {
      case .badResponse: return "Couldn't reach Project Gutenberg. Check your connection."
      case .noEpub: return "This title has no downloadable EPUB edition."
      }
    }
  }

  // MARK: Search

  static func search(_ query: String, filters: SearchFilters = SearchFilters()) async throws
    -> [Item]
  {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var components = URLComponents(string: "https://gutendex.com/books")!
    var queryItems = [
      URLQueryItem(name: "search", value: trimmed),
      URLQueryItem(name: "mime_type", value: "application/epub+zip"),
    ]
    if let lang = filters.language.gutenbergCode {
      queryItems.append(URLQueryItem(name: "languages", value: lang))
    }
    if filters.sort == .popular {
      queryItems.append(URLQueryItem(name: "sort", value: "popular"))
    }
    components.queryItems = queryItems
    guard let url = components.url else { throw ServiceError.badResponse }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20

    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ServiceError.badResponse
    }

    let decoded = try JSONDecoder().decode(Response.self, from: data)
    return decoded.results.map { doc in
      Item(
        id: doc.id,
        title: doc.title,
        author: doc.authors.first?.name ?? "Unknown author",
        epubURL: epubURL(from: doc.formats),
        coverURL: doc.formats["image/jpeg"].flatMap(URL.init(string:)),
        subjects: doc.subjects ?? []
      )
    }
  }

  /// Downloads the EPUB bytes for an item.
  static func downloadEpub(from url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 90
    // Download to a temporary file rather than holding an unbounded response in
    // memory. EpubArchive applies the same limit again before expanding it.
    let (temporaryURL, response) = try await URLSession.shared.download(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      response.expectedContentLength <= Int64(EpubArchive.maximumArchiveBytes)
        || response.expectedContentLength < 0
    else {
      throw ServiceError.noEpub
    }
    let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size > 1000, size <= EpubArchive.maximumArchiveBytes,
      let data = try? Data(contentsOf: temporaryURL, options: .mappedIfSafe)
    else { throw ServiceError.noEpub }
    return data
  }

  /// Gutendex exposes several epub keys; prefer one without ".images" noimages
  /// fallbacks. Keys look like "application/epub+zip".
  private static func epubURL(from formats: [String: String]) -> URL? {
    for (key, value) in formats where key.hasPrefix("application/epub+zip") {
      if let url = URL(string: value), !value.contains(".noimages") { return url }
    }
    if let value = formats["application/epub+zip"] { return URL(string: value) }
    return nil
  }

  // MARK: Decoding

  private struct Response: Decodable {
    let results: [Doc]
  }

  private struct Doc: Decodable {
    let id: Int
    let title: String
    let authors: [Author]
    let subjects: [String]?
    let formats: [String: String]
  }

  private struct Author: Decodable {
    let name: String
  }
}

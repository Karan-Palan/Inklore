import Foundation
import SwiftData
import SwiftUI

/// Where a discoverable book comes from. Project Gutenberg ships real EPUBs
/// (formatting + images intact); the Internet Archive is the plain-text fallback.
enum BookSource: String, CaseIterable, Identifiable {
  case gutenberg = "Project Gutenberg"
  case internetArchive = "Internet Archive"

  var id: String { rawValue }
  var deliversEpub: Bool { self == .gutenberg }
  var badgeColor: Color { self == .gutenberg ? Theme.accent : Theme.inkSoft }
  var shortName: String { self == .gutenberg ? "Gutenberg" : "Archive" }
}

/// Which sources to query — like the Internet Archive / libgen source toggles.
enum SourceFilter: String, CaseIterable, Identifiable {
  case all = "All sources"
  case gutenberg = "Gutenberg"
  case internetArchive = "Archive"

  var id: String { rawValue }
}

/// Format filter, mirroring the "EPUB / Text / PDF" facets readers expect.
enum FormatFilter: String, CaseIterable, Identifiable {
  case all = "Any format"
  case epub = "EPUB"
  case text = "Text"

  var id: String { rawValue }
}

/// Language facet (the most common ones — Archive/Gutenberg support many more).
enum LanguageFilter: String, CaseIterable, Identifiable {
  case any = "Any language"
  case english = "English"
  case french = "French"
  case spanish = "Spanish"
  case german = "German"
  case italian = "Italian"

  var id: String { rawValue }

  /// Gutendex two-letter code.
  var gutenbergCode: String? {
    switch self {
    case .any: return nil
    case .english: return "en"
    case .french: return "fr"
    case .spanish: return "es"
    case .german: return "de"
    case .italian: return "it"
    }
  }

  /// Internet Archive language facet value.
  var archiveValue: String? {
    switch self {
    case .any: return nil
    case .english: return "English"
    case .french: return "French"
    case .spanish: return "Spanish"
    case .german: return "German"
    case .italian: return "Italian"
    }
  }
}

/// Sort order, matching the Archive/libgen result sorting.
enum SortOrder: String, CaseIterable, Identifiable {
  case relevance = "Best match"
  case popular = "Most read"
  case newest = "Newest"
  case title = "Title A–Z"

  var id: String { rawValue }
}

/// The full set of facets applied to a Discover search.
struct SearchFilters: Equatable {
  var source: SourceFilter = .all
  var format: FormatFilter = .all
  var language: LanguageFilter = .any
  var sort: SortOrder = .relevance

  /// Count of facets that aren't at their default — for a badge in the UI.
  var activeCount: Int {
    var n = 0
    if source != .all { n += 1 }
    if format != .all { n += 1 }
    if language != .any { n += 1 }
    if sort != .relevance { n += 1 }
    return n
  }
}

/// A single unified search result spanning both sources.
struct DiscoverResult: Identifiable, Hashable {
  let id: String
  let title: String
  let author: String
  let detail: String
  let source: BookSource
  /// Gutenberg: direct EPUB URL. Internet Archive: nil (text fetched by identifier).
  let epubURL: URL?
  let coverURL: URL?
  /// Internet Archive identifier (empty for Gutenberg).
  let archiveIdentifier: String
}

/// Aggregates the two legal sources into one ranked result list, honoring the
/// active filters (source / format / language / sort).
enum BookSearch {

  static func search(
    _ query: String, filters: SearchFilters = SearchFilters()
  ) async -> (results: [DiscoverResult], error: String?) {
    let wantGutenberg = filters.source != .internetArchive && filters.format != .text
    let wantArchive = filters.source != .gutenberg && filters.format != .epub

    async let gutenberg = wantGutenberg ? safeGutenberg(query, filters: filters) : []
    async let archive = wantArchive ? safeArchive(query, filters: filters) : []

    let (gut, arc) = await (gutenberg, archive)
    var combined = gut + arc

    // De-dupe by case-insensitive title+author so the same classic from both
    // sources doesn't appear twice (Gutenberg wins because it's listed first).
    var seen = Set<String>()
    combined = combined.filter { item in
      let key = (item.title + "|" + item.author).lowercased()
      return seen.insert(key).inserted
    }

    combined = rank(combined, query: query, sort: filters.sort)
    combined = filterRelevant(combined, query: query)

    let error =
      combined.isEmpty ? "No free books found for “\(query)”. Try another title or author." : nil
    return (combined, error)
  }

  /// Drops results that don't actually match the query. The Archive's search
  /// returns loosely-related items; we require at least one query term to appear
  /// in the title or author so unrelated books never show up.
  private static func filterRelevant(
    _ items: [DiscoverResult], query: String
  ) -> [DiscoverResult] {
    let terms =
      query.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 1 }
    guard !terms.isEmpty else { return items }

    let filtered = items.filter { r in
      let haystack = (r.title + " " + r.author).lowercased()
      return terms.contains { haystack.contains($0) }
    }
    // If filtering nuked everything (e.g. a very short/odd query), fall back to
    // the ranked list rather than showing an empty screen.
    return filtered.isEmpty ? items : filtered
  }

  /// Local re-ranking so results feel relevant. Title matches beat description
  /// matches, junk-looking titles sink, then the chosen sort is applied.
  private static func rank(
    _ items: [DiscoverResult], query: String, sort: SortOrder
  ) -> [DiscoverResult] {
    let terms =
      query.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 1 }

    func score(_ r: DiscoverResult) -> Int {
      let title = r.title.lowercased()
      let author = r.author.lowercased()
      var s = 0
      for term in terms {
        if title == term { s += 100 }
        if title.hasPrefix(term) { s += 40 }
        if title.contains(term) { s += 25 }
        if author.contains(term) { s += 15 }
      }
      // Penalize obvious dump/collection titles with no spaces or odd casing.
      if !r.title.contains(" ") && r.title.count > 12 { s -= 30 }
      if r.author == "Unknown author" { s -= 8 }
      // Slight preference for full EPUBs.
      if r.source == .gutenberg { s += 5 }
      return s
    }

    switch sort {
    case .relevance:
      return items.sorted { score($0) > score($1) }
    case .title:
      return items.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
    case .popular, .newest:
      // Source services already requested these orders; keep their order but
      // still float strong title matches up a little.
      return items.sorted { score($0) > score($1) }
    }
  }

  private static func safeGutenberg(_ query: String, filters: SearchFilters) async
    -> [DiscoverResult]
  {
    do {
      let items = try await GutenbergService.search(query, filters: filters)
      return items.compactMap { item in
        guard let epub = item.epubURL else { return nil }
        let detail = item.subjects.prefix(2).joined(separator: " · ")
        return DiscoverResult(
          id: "gutenberg-\(item.id)",
          title: item.title,
          author: item.author,
          detail: detail.isEmpty ? "Full EPUB · images & formatting" : detail,
          source: .gutenberg,
          epubURL: epub,
          coverURL: item.coverURL,
          archiveIdentifier: ""
        )
      }
    } catch {
      return []
    }
  }

  private static func safeArchive(_ query: String, filters: SearchFilters) async -> [DiscoverResult]
  {
    do {
      let items = try await InternetArchiveService.search(query, filters: filters)
      return items.map { item in
        DiscoverResult(
          id: "archive-\(item.identifier)",
          title: item.title,
          author: item.author,
          detail: item.description.isEmpty
            ? (item.year.map { "Published \($0)" } ?? "Plain-text edition") : item.description,
          source: .internetArchive,
          epubURL: nil,
          coverURL: item.coverURL,
          archiveIdentifier: item.identifier
        )
      }
    } catch {
      return []
    }
  }
}

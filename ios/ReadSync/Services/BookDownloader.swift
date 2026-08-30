import Foundation
import SwiftData
import SwiftUI

/// Centralized "turn a discoverable book into a saved `Book`" pipeline, shared by
/// Search (manual downloads) and Onboarding (genre starter-shelf seeding). Keeps
/// the EPUB-extract / text-fetch logic in one place so both paths stay in sync.
enum BookDownloader {

  private struct PreparedEpub: Sendable {
    let folderName: String
    let narration: String
    let spineCount: Int
  }

  /// Downloads a single discover result and inserts it into the context. Returns
  /// the inserted book on success. Throws on network / parse failure.
  @MainActor
  @discardableResult
  static func download(_ result: DiscoverResult, into context: ModelContext) async throws -> Book {
    let palette = coverPalette(for: result.id)
    let book: Book

    switch result.source {
    case .gutenberg:
      guard let url = result.epubURL else { throw GutenbergService.ServiceError.noEpub }
      let data = try await GutenbergService.downloadEpub(from: url)
      // ZIP expansion, OPF parsing, and narration flattening can take seconds
      // for image-heavy books. Keep all of it off the SwiftUI/SwiftData actor.
      let prepared = try await Task.detached(priority: .utility) {
        let folder = try EpubArchive.extract(data)
        guard let document = EpubDocument(folderName: folder), !document.chapters.isEmpty else {
          EpubArchive.removeFolder(named: folder)
          throw EpubArchive.ArchiveError.corrupt
        }
        return PreparedEpub(
          folderName: folder, narration: document.plainText(), spineCount: document.chapters.count)
      }.value
      book = Book(
        title: result.title,
        author: result.author,
        bookDescription: result.detail.isEmpty
          ? "Downloaded from Project Gutenberg." : result.detail,
        category: "Downloads",
        coverHexStart: palette.0,
        coverHexEnd: palette.1,
        ratingTimesThousand: 0,
        storedText: prepared.narration,
        isDownloaded: true,
        sourceIdentifier: result.id,
        format: .epub,
        epubFolderName: prepared.folderName,
        spineCount: prepared.spineCount,
        sourceName: result.source.rawValue,
        coverImageURL: result.coverURL?.absoluteString ?? ""
      )

    case .internetArchive:
      let text = try await InternetArchiveService.downloadText(for: result.archiveIdentifier)
      book = Book(
        title: result.title,
        author: result.author,
        bookDescription: result.detail.isEmpty
          ? "Downloaded from the Internet Archive." : result.detail,
        category: "Downloads",
        coverHexStart: palette.0,
        coverHexEnd: palette.1,
        ratingTimesThousand: 0,
        storedText: text,
        isDownloaded: true,
        sourceIdentifier: result.id,
        format: .text,
        sourceName: result.source.rawValue,
        coverImageURL: result.coverURL?.absoluteString ?? ""
      )
    }

    context.insert(book)
    do {
      try context.save()
    } catch {
      context.delete(book)
      if case .gutenberg = result.source { EpubArchive.removeFolder(named: book.epubFolderName) }
      throw error
    }
    return book
  }

  /// Resolves a curated title/author into a real Gutenberg EPUB result, preferring
  /// an exact title match. Returns nil if the search finds nothing usable.
  static func resolve(title: String, author: String) async -> DiscoverResult? {
    let outcome = await BookSearch.search(
      "\(title) \(author)",
      filters: SearchFilters(
        source: .gutenberg, format: .epub, language: .english, sort: .relevance)
    )
    let wanted = title.lowercased()
    return outcome.results.first { $0.title.lowercased().contains(wanted) }
      ?? outcome.results.first
  }

  /// Deterministic cover gradient derived from the identifier.
  static func coverPalette(for id: String) -> (UInt, UInt) {
    let palettes: [(UInt, UInt)] = [
      (0x2E3A59, 0x6C7A9C), (0x0F5C5B, 0x2FA39C), (0x7A1F3D, 0xC2703D),
      (0x4A3B2A, 0xB08545), (0x1F4F6E, 0x57A0C2), (0x37314A, 0x8A7BB0),
    ]
    return palettes[Int(id.hashValue.magnitude % UInt(palettes.count))]
  }
}

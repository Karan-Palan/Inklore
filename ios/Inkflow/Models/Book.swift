import Foundation
import SwiftData
import SwiftUI

/// A book in the user's library. Holds metadata, the full body text (either
/// original sample prose or a real book downloaded from the Internet Archive),
/// reading progress as a character offset, highlights, and notes.
@Model
final class Book {
  @Attribute(.unique) var id: UUID
  var title: String
  var author: String
  var bookDescription: String
  var category: String
  var coverHexStart: UInt
  var coverHexEnd: UInt

  /// Reading position as a character offset (NSString/utf16 length based) into
  /// `bodyText`. This is what drives progress for reflowable text.
  var charOffset: Int
  /// Page index + page count from the last pagination (display only).
  var currentPage: Int
  var totalPages: Int

  var hasAudio: Bool
  var audioPositionSeconds: Int
  var isFinished: Bool
  var addedDate: Date
  var lastOpenedDate: Date?
  var ratingTimesThousand: Int  // store 4.7 as 4700 to avoid Double in model

  /// Real downloaded books store their whole text here. Sample books leave this
  /// empty and assemble `bodyText` from `chapters`.
  var storedText: String
  var isDownloaded: Bool
  /// Internet Archive identifier for downloaded books (empty for samples).
  var sourceIdentifier: String

  /// Storage format. Plain-text + sample books use `.text`; books downloaded as
  /// a real EPUB use `.epub` and render with full HTML/CSS/images.
  var formatRaw: String = BookFormat.text.rawValue
  /// Folder name (under the app's epub store) holding the extracted EPUB.
  var epubFolderName: String = ""
  /// Reading position for EPUB books: spine (chapter) index + vertical scroll
  /// fraction within that chapter.
  var spineIndex: Int = 0
  var spineCount: Int = 0
  var chapterScroll: Double = 0
  /// File name (under the app's pdf store) holding the imported PDF.
  var pdfFileName: String = ""
  /// Reading position for PDF books: 0-based page index + total page count.
  var pdfPageIndex: Int = 0
  var pdfPageCount: Int = 0
  /// Where the book came from, for a source badge ("Internet Archive", "Project Gutenberg").
  var sourceName: String = ""
  /// Remote cover artwork URL (from the source catalog), shown in the library.
  var coverImageURL: String = ""

  // Chapter text content (original placeholder prose for sample books).
  var chapters: [Chapter]

  @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
  var highlights: [Highlight] = []

  @Relationship(deleteRule: .cascade, inverse: \Note.book)
  var notes: [Note] = []

  init(
    id: UUID = UUID(),
    title: String,
    author: String,
    bookDescription: String,
    category: String,
    coverHexStart: UInt,
    coverHexEnd: UInt,
    totalPages: Int = 0,
    currentPage: Int = 0,
    charOffset: Int = 0,
    hasAudio: Bool = true,
    audioPositionSeconds: Int = 0,
    isFinished: Bool = false,
    addedDate: Date = .now,
    lastOpenedDate: Date? = nil,
    ratingTimesThousand: Int = 4500,
    storedText: String = "",
    isDownloaded: Bool = false,
    sourceIdentifier: String = "",
    format: BookFormat = .text,
    epubFolderName: String = "",
    spineCount: Int = 0,
    pdfFileName: String = "",
    pdfPageCount: Int = 0,
    sourceName: String = "",
    coverImageURL: String = "",
    chapters: [Chapter] = []
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.bookDescription = bookDescription
    self.category = category
    self.coverHexStart = coverHexStart
    self.coverHexEnd = coverHexEnd
    self.totalPages = totalPages
    self.currentPage = currentPage
    self.charOffset = charOffset
    self.hasAudio = hasAudio
    self.audioPositionSeconds = audioPositionSeconds
    self.isFinished = isFinished
    self.addedDate = addedDate
    self.lastOpenedDate = lastOpenedDate
    self.ratingTimesThousand = ratingTimesThousand
    self.storedText = storedText
    self.isDownloaded = isDownloaded
    self.sourceIdentifier = sourceIdentifier
    self.formatRaw = format.rawValue
    self.epubFolderName = epubFolderName
    self.spineCount = spineCount
    self.pdfFileName = pdfFileName
    self.pdfPageCount = pdfPageCount
    self.sourceName = sourceName
    self.coverImageURL = coverImageURL
    self.chapters = chapters
  }

  var format: BookFormat {
    get { BookFormat(rawValue: formatRaw) ?? .text }
    set { formatRaw = newValue.rawValue }
  }

  var isEpub: Bool { format == .epub }
  var isPdf: Bool { format == .pdf }

  var rating: Double { Double(ratingTimesThousand) / 1000 }

  /// The full reflowable body of the book. Downloaded books use `storedText`;
  /// sample books assemble it from their chapters.
  var bodyText: String {
    if !storedText.isEmpty { return storedText }
    return
      chapters
      .map { chapter in
        chapter.title + "\n\n" + chapter.paragraphs.joined(separator: "\n\n")
      }
      .joined(separator: "\n\n\n")
  }

  /// utf16 length, matching the offsets used for pagination and highlights.
  var bodyNSLength: Int { (bodyText as NSString).length }

  var progress: Double {
    if isPdf {
      guard pdfPageCount > 0 else { return 0 }
      return min(1, Double(pdfPageIndex + 1) / Double(pdfPageCount))
    }
    if isEpub {
      guard spineCount > 0 else { return 0 }
      let perChapter = 1.0 / Double(spineCount)
      return min(1, (Double(spineIndex) + min(max(chapterScroll, 0), 1)) * perChapter)
    }
    let len = bodyNSLength
    guard len > 0 else { return 0 }
    return min(1, Double(charOffset) / Double(len))
  }

  var isStarted: Bool {
    charOffset > 0 || spineIndex > 0 || chapterScroll > 0 || pdfPageIndex > 0 || isFinished
  }

  /// Every book with extractable text can be narrated via on-device TTS. For
  /// EPUB books we store flattened narration text in `storedText` at download
  /// time (rendering still uses the original HTML); plain-text books use it
  /// directly. `bodyText` falls back to chapters only for legacy/sample books.
  var canListen: Bool { bodyNSLength > 0 }
}

/// Storage/render format for a book.
enum BookFormat: String, Codable {
  case text
  case epub
  case pdf
}

/// A chapter stored inline on the book. Codable so it lives in the SwiftData blob.
struct Chapter: Codable, Identifiable, Hashable, Sendable {
  var id: UUID = UUID()
  var title: String
  var paragraphs: [String]
}

/// A highlighted passage with a swatch color and global character range.
@Model
final class Highlight {
  @Attribute(.unique) var id: UUID
  var text: String
  var colorName: String
  var chapterTitle: String
  var startOffset: Int
  var endOffset: Int
  var createdDate: Date
  var book: Book?

  init(
    id: UUID = UUID(),
    text: String,
    colorName: String,
    chapterTitle: String = "",
    startOffset: Int = 0,
    endOffset: Int = 0,
    createdDate: Date = .now,
    book: Book? = nil
  ) {
    self.id = id
    self.text = text
    self.colorName = colorName
    self.chapterTitle = chapterTitle
    self.startOffset = startOffset
    self.endOffset = endOffset
    self.createdDate = createdDate
    self.book = book
  }

  var range: NSRange { NSRange(location: startOffset, length: max(0, endOffset - startOffset)) }
}

/// A free-text note attached to a passage.
@Model
final class Note {
  @Attribute(.unique) var id: UUID
  var passage: String
  var body: String
  var chapterTitle: String
  var startOffset: Int
  var createdDate: Date
  var book: Book?

  init(
    id: UUID = UUID(),
    passage: String,
    body: String,
    chapterTitle: String = "",
    startOffset: Int = 0,
    createdDate: Date = .now,
    book: Book? = nil
  ) {
    self.id = id
    self.passage = passage
    self.body = body
    self.chapterTitle = chapterTitle
    self.startOffset = startOffset
    self.createdDate = createdDate
    self.book = book
  }
}

/// A single reading or listening session — feeds the Stats screen with real data.
@Model
final class ReadingSession {
  @Attribute(.unique) var id: UUID
  var date: Date
  var minutes: Int
  var pagesRead: Int
  var wasListening: Bool

  init(
    id: UUID = UUID(),
    date: Date = .now,
    minutes: Int,
    pagesRead: Int = 0,
    wasListening: Bool = false
  ) {
    self.id = id
    self.date = date
    self.minutes = minutes
    self.pagesRead = pagesRead
    self.wasListening = wasListening
  }
}

/// The user's reading goal + profile. Single-row settings model.
@Model
final class ReadingGoal {
  @Attribute(.unique) var id: UUID
  var displayName: String
  var weeklyMinutesTarget: Int
  var dailyMinutesTarget: Int
  var currentStreak: Int
  var longestStreak: Int

  init(
    id: UUID = UUID(),
    displayName: String = "Reader",
    weeklyMinutesTarget: Int = 150,
    dailyMinutesTarget: Int = 20,
    currentStreak: Int = 0,
    longestStreak: Int = 0
  ) {
    self.id = id
    self.displayName = displayName
    self.weeklyMinutesTarget = weeklyMinutesTarget
    self.dailyMinutesTarget = dailyMinutesTarget
    self.currentStreak = currentStreak
    self.longestStreak = longestStreak
  }
}

/// Highlight swatch palette shared across reader + notebook.
enum HighlightColor: String, CaseIterable, Identifiable {
  case yellow, green, blue, pink

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .yellow: return Theme.highlightYellow
    case .green: return Theme.highlightGreen
    case .blue: return Theme.highlightBlue
    case .pink: return Theme.highlightPink
    }
  }

  var uiColor: UIColor { UIColor(color) }
}

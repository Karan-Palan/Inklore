import SwiftUI
import UIKit

/// Splits a long body of text into fixed-size pages using TextKit, exactly like
/// a paginated e-reader. Each page is an `NSRange` into the source string, so
/// reading position (a character offset) maps cleanly to a page and back.
struct Paginator {
  let pageRanges: [NSRange]
  let attributed: NSAttributedString

  /// Build pages for the given text, font, and page size.
  static func paginate(
    text: String,
    font: UIFont,
    textColor: UIColor,
    lineSpacing: CGFloat,
    size: CGSize
  ) -> Paginator {
    paginate(
      text: text, font: font, textColor: textColor, lineSpacing: lineSpacing, size: size,
      shouldCancel: { false }
    ) ?? Paginator(
      pageRanges: [NSRange(location: 0, length: (text as NSString).length)],
      attributed: NSAttributedString(string: text))
  }

  /// Runs layout in a fresh utility task. TextKit instances are deliberately
  /// created and used entirely inside that task; the completed paginator is
  /// then consumed by the main-actor reader. Cancelling a newer layout request
  /// also cancels the old worker between page containers.
  static func paginateInBackground(
    text: String,
    font: UIFont,
    textColor: UIColor,
    lineSpacing: CGFloat,
    size: CGSize
  ) async -> Paginator? {
    let worker = Task.detached(priority: .userInitiated) {
      paginate(
        text: text, font: font, textColor: textColor, lineSpacing: lineSpacing, size: size,
        shouldCancel: { Task.isCancelled })
    }
    return await withTaskCancellationHandler {
      await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private static func paginate(
    text: String,
    font: UIFont,
    textColor: UIColor,
    lineSpacing: CGFloat,
    size: CGSize,
    shouldCancel: () -> Bool
  ) -> Paginator? {
    guard !shouldCancel() else { return nil }
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.paragraphSpacing = lineSpacing * 1.6
    paragraphStyle.hyphenationFactor = 0.7
    paragraphStyle.alignment = .justified

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)

    let textStorage = NSTextStorage(attributedString: attributed)
    let layoutManager = NSLayoutManager()
    textStorage.addLayoutManager(layoutManager)

    var ranges: [NSRange] = []
    // Guard against a degenerate size.
    let pageSize = CGSize(width: max(40, size.width), height: max(40, size.height))

    var lastRangeEnd = 0
    let totalLength = attributed.length

    while lastRangeEnd < totalLength {
      guard !shouldCancel() else { return nil }
      let container = NSTextContainer(size: pageSize)
      container.lineFragmentPadding = 0
      layoutManager.addTextContainer(container)

      let glyphRange = layoutManager.glyphRange(for: container)
      let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

      if charRange.length == 0 { break }
      ranges.append(charRange)
      lastRangeEnd = charRange.location + charRange.length

      // Safety: avoid an unbounded loop on pathological input.
      if ranges.count > 20000 { break }
    }

    if ranges.isEmpty {
      ranges = [NSRange(location: 0, length: totalLength)]
    }

    guard !shouldCancel() else { return nil }
    return Paginator(pageRanges: ranges, attributed: attributed)
  }

  /// The page index that contains a given character offset.
  func pageIndex(for charOffset: Int) -> Int {
    guard !pageRanges.isEmpty else { return 0 }
    // This is called for every spoken word during read-along. A linear scan
    // made long books progressively slower, so keep the lookup logarithmic.
    var lower = 0
    var upper = pageRanges.count - 1
    while lower <= upper {
      let middle = lower + (upper - lower) / 2
      let range = pageRanges[middle]
      if charOffset < range.location {
        upper = middle - 1
      } else if charOffset >= range.location + range.length {
        lower = middle + 1
      } else {
        return middle
      }
    }
    return min(max(lower, 0), pageRanges.count - 1)
  }

  /// The character offset at the start of a page (for saving position).
  func startOffset(of pageIndex: Int) -> Int {
    guard pageRanges.indices.contains(pageIndex) else { return 0 }
    return pageRanges[pageIndex].location
  }

  var pageCount: Int { pageRanges.count }
}

/// A deliberately small main-actor cache for recently-used reader layouts.
/// Each entry owns a full attributed copy of the book, so keeping this bounded
/// is important for imports near the text-size limit.
@MainActor
final class PaginatorCache {
  struct Key: Hashable {
    let bookID: UUID
    let textLength: Int
    let fontName: String
    let fontSize: CGFloat
    let textColorKey: String
    let lineSpacing: CGFloat
    let width: CGFloat
    let height: CGFloat
  }

  static let shared = PaginatorCache()

  private let capacity = 2
  private var entries: [Key: Paginator] = [:]
  private var recency: [Key] = []

  func paginator(for key: Key) -> Paginator? {
    guard let paginator = entries[key] else { return nil }
    touch(key)
    return paginator
  }

  func insert(_ paginator: Paginator, for key: Key) {
    entries[key] = paginator
    touch(key)
    while recency.count > capacity {
      entries.removeValue(forKey: recency.removeFirst())
    }
  }

  private func touch(_ key: Key) {
    recency.removeAll { $0 == key }
    recency.append(key)
  }
}

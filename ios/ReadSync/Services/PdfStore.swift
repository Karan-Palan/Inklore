import Foundation
import PDFKit

/// Stores imported PDF files on disk and extracts their text so PDF books can be
/// both rendered (PDFKit) and narrated (on-device TTS). Dependency-free.
enum PdfStore {

  /// Keep the SwiftData text field and TTS input at a practical size. The PDF
  /// itself is still retained in full and can be read in PDFKit.
  static let maximumExtractedTextLength = 2_000_000
  private static let maximumPageCount = 3_000

  enum StoreError: LocalizedError {
    case notPdf
    case tooLarge
    case writeFailed

    var errorDescription: String? {
      switch self {
      case .notPdf: return "This file isn't a readable PDF."
      case .tooLarge: return "This PDF has too many pages to import safely on this device."
      case .writeFailed: return "Couldn't save the PDF to your device."
      }
    }
  }

  /// Root directory where imported PDFs live.
  static var storeURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let url = base.appendingPathComponent("Pdfs", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func fileURL(named name: String) -> URL {
    storeURL.appendingPathComponent(name)
  }

  static func removeFile(named name: String) {
    guard !name.isEmpty else { return }
    try? FileManager.default.removeItem(at: fileURL(named: name))
  }

  /// What a saved PDF exposes after import.
  struct Saved {
    let fileName: String
    let pageCount: Int
    let title: String?
    let author: String?
    let text: String
  }

  /// Persists the PDF `data` into a uniquely-named file and returns its metadata,
  /// page count, and extracted narration text. Throws if the bytes aren't a PDF.
  static func save(_ data: Data) throws -> Saved {
    guard let document = PDFDocument(data: data), document.pageCount > 0 else {
      throw StoreError.notPdf
    }
    guard document.pageCount <= maximumPageCount else { throw StoreError.tooLarge }

    let fileName = UUID().uuidString + ".pdf"
    do {
      try data.write(to: fileURL(named: fileName), options: .atomic)
    } catch {
      throw StoreError.writeFailed
    }

    let attrs = document.documentAttributes
    let title = attrs?[PDFDocumentAttribute.titleAttribute] as? String
    let author = attrs?[PDFDocumentAttribute.authorAttribute] as? String

    return Saved(
      fileName: fileName,
      pageCount: document.pageCount,
      title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
      author: author?.trimmingCharacters(in: .whitespacesAndNewlines),
      text: extractText(from: document)
    )
  }

  /// Flattened text of the whole document, page by page, for TTS narration.
  static func extractText(from document: PDFDocument) -> String {
    var parts: [String] = []
    var remaining = maximumExtractedTextLength
    for index in 0..<document.pageCount {
      guard remaining > 0 else { break }
      guard let page = document.page(at: index) else { continue }
      let raw = page.string ?? ""
      let cleaned = clean(raw)
      guard !cleaned.isEmpty else { continue }
      let ns = cleaned as NSString
      if ns.length <= remaining {
        parts.append(cleaned)
        remaining -= ns.length
      } else {
        parts.append(ns.substring(to: remaining))
        remaining = 0
      }
    }
    return parts.joined(separator: "\n\n")
  }

  /// Collapse hard-wrapped lines into paragraphs and drop standalone page numbers.
  private static func clean(_ raw: String) -> String {
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = normalized.components(separatedBy: "\n")
    var paragraphs: [String] = []
    var current = ""
    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        if !current.isEmpty {
          paragraphs.append(current)
          current = ""
        }
        continue
      }
      if isPageArtifact(line) { continue }
      current += current.isEmpty ? line : " " + line
    }
    if !current.isEmpty { paragraphs.append(current) }
    return paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A standalone line that is just a page number or running page marker, not prose.
  private static func isPageArtifact(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }

    // Pure digits on their own line (any length) — page numbers / extraction artifacts.
    if trimmed.allSatisfy(\.isNumber) { return true }

    // "Page 12", "p. 12", "12 of 482", roman-numeral folios like "xii".
    let lowered = trimmed.lowercased()
    if lowered.range(of: #"^(page|p\.?)\s*\d+$"#, options: .regularExpression) != nil {
      return true
    }
    if lowered.range(of: #"^\d+\s+of\s+\d+$"#, options: .regularExpression) != nil { return true }
    if lowered.range(of: #"^[ivxlcdm]{1,6}$"#, options: .regularExpression) != nil { return true }

    return false
  }
}

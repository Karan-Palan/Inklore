import SwiftUI

/// Routes a book to the correct reader for its storage format: PDFs render with
/// PDFKit, EPUBs with the WKWebView reader, and plain text with the paginated
/// TextKit reader. One entry point so callers don't branch on format everywhere.
struct BookReader: View {
  let book: Book

  var body: some View {
    Group {
      switch book.format {
      case .pdf:
        PdfReaderView(book: book)
      case .epub:
        EpubReaderView(book: book)
      case .text:
        ReaderView(book: book)
      }
    }
    .__tenxTrackView("BookReader")
  }
}

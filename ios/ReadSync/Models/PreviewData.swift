import SwiftData
import SwiftUI

/// Shared in-memory container for SwiftUI previews, seeded with sample data.
enum PreviewData {
  @MainActor static let container: ModelContainer = {
    let container = try! ModelContainer(
      for: Book.self, Highlight.self, Note.self, ReadingSession.self, ReadingGoal.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for book in SampleLibrary.makeBooks() {
      context.insert(book)
    }
    context.insert(SampleLibrary.makeGoal())

    // A few real-looking sessions so the Stats preview has data.
    let cal = Calendar.current
    for (offset, minutes) in [42, 0, 33, 25, 51, 18, 39].enumerated() where minutes > 0 {
      if let day = cal.date(byAdding: .day, value: -offset, to: .now) {
        context.insert(
          ReadingSession(
            date: day, minutes: minutes, pagesRead: minutes / 2, wasListening: offset % 3 == 0))
      }
    }

    if let first = try? context.fetch(FetchDescriptor<Book>()).first {
      context.insert(
        Highlight(
          text: "The tide came in apologetic and went out forgiven.",
          colorName: HighlightColor.yellow.rawValue, book: first))
      context.insert(
        Note(
          passage: "Reminding something of itself.",
          body: "This is the whole thesis of the book in one line.", book: first))
    }
    try? context.save()
    return container
  }()

  @MainActor static var sampleBook: Book {
    (try? container.mainContext.fetch(FetchDescriptor<Book>()).first)
      ?? SampleLibrary.makeBooks()[0]
  }
}

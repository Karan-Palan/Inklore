import Foundation

/// Original placeholder library content seeded on first launch so the app isn't
/// empty before the user downloads real books from Discover. No real titles,
/// authors, or copyrighted text — everything here is invented sample prose.
enum SampleLibrary {

  static func makeBooks() -> [Book] {
    var books: [Book] = []
    books.append(
      Book(
        title: "The Lantern of Quiet Hours",
        author: "Marigold Ashcroft",
        bookDescription:
          "A clockmaker in a fog-bound harbor town discovers that the lanterns she repairs each hold a single borrowed memory — and one of them is hers.",
        category: "Literature & Fiction",
        coverHexStart: 0x2E3A59,
        coverHexEnd: 0x6C7A9C,
        currentPage: 4,
        lastOpenedDate: Date().addingTimeInterval(-3600),
        ratingTimesThousand: 4700,
        chapters: chaptersLantern
      ))
    books.append(
      Book(
        title: "Saltwater Arithmetic",
        author: "Dov Renner",
        bookDescription:
          "A marine biologist and a retired fisherman count what the tide takes and leaves behind, in a memoir about loss measured one wave at a time.",
        category: "Biographies",
        coverHexStart: 0x0F5C5B,
        coverHexEnd: 0x2FA39C,
        isFinished: true,
        lastOpenedDate: Date().addingTimeInterval(-86400 * 2),
        ratingTimesThousand: 4500,
        chapters: chaptersGeneric(title: "Saltwater Arithmetic")
      ))
    books.append(
      Book(
        title: "Cinders & Signal Fire",
        author: "Petra Vane",
        bookDescription:
          "When the beacon network fails on the longest night of the year, a teenage courier must carry a warning across seven sleeping kingdoms.",
        category: "Romance",
        coverHexStart: 0x7A1F3D,
        coverHexEnd: 0xC2703D,
        ratingTimesThousand: 4800,
        chapters: chaptersGeneric(title: "Cinders & Signal Fire")
      ))
    books.append(
      Book(
        title: "The Mapmaker's Apology",
        author: "Idris Holloway",
        bookDescription:
          "Every map he drew was a small lie of omission. Now the territories he erased are writing back.",
        category: "Literature & Fiction",
        coverHexStart: 0x4A3B2A,
        coverHexEnd: 0xB08545,
        currentPage: 8,
        lastOpenedDate: Date().addingTimeInterval(-86400),
        ratingTimesThousand: 4600,
        chapters: chaptersGeneric(title: "The Mapmaker's Apology")
      ))
    books.append(
      Book(
        title: "How to Fold a River",
        author: "Wren Adeyemi",
        bookDescription:
          "Field notes on slowing down, gathered by a cartographer who decided to walk the length of every river she ever drew.",
        category: "Self-Help",
        coverHexStart: 0x1F4F6E,
        coverHexEnd: 0x57A0C2,
        ratingTimesThousand: 4900,
        chapters: chaptersGeneric(title: "How to Fold a River")
      ))
    return books
  }

  static func makeGoal() -> ReadingGoal {
    ReadingGoal(displayName: "Reader", weeklyMinutesTarget: 150, dailyMinutesTarget: 20)
  }

  // MARK: - Sample prose

  static let categories = [
    "All", "Romance", "Literature & Fiction", "Science Fiction",
    "Biographies", "History", "Self-Help", "Mystery",
  ]

  private static let loremParagraphs: [String] = [
    "The harbor woke slowly that morning, the way old things do — first a creak, then a sigh, then the long exhale of fog peeling back from the water. She had counted the bells of every dawn for eleven years and still could not say which one belonged to her.",
    "There is a particular silence that lives inside a workshop after the tools are set down. It is not empty. It is full of every motion you did not make, every cut you considered and refused. She listened to that silence the way other people listen to music.",
    "He had been told, once, that memory was a room you could only enter from the outside. You pressed your face to the glass and watched yourself live, and the glass was always a little colder than you expected.",
    "Outside, the gulls argued over nothing, which was the only thing they ever had. The tide came in apologetic and went out forgiven. Between the two, the whole town held its breath and called it ordinary life.",
    "She turned the small brass key and the mechanism answered — not with sound exactly, but with the absence of resistance, the feeling of a thing remembering how it was meant to move. That, she thought, was all repair ever was. Reminding something of itself.",
    "By noon the light had changed its mind three times. The lanterns waited in their rows, patient as pews, each one holding a flame that was not quite fire and a memory that was not quite hers.",
  ]

  /// Repeat the prose so sample books fill several real pages.
  private static var longParagraphs: [String] {
    Array(repeating: loremParagraphs, count: 4).flatMap { $0 }
  }

  static var chaptersLantern: [Chapter] {
    [
      Chapter(title: "One — The Borrowed Flame", paragraphs: longParagraphs),
      Chapter(title: "Two — Low Tide", paragraphs: longParagraphs.reversed()),
      Chapter(title: "Three — What the Glass Kept", paragraphs: longParagraphs),
    ]
  }

  static func chaptersGeneric(title: String) -> [Chapter] {
    [
      Chapter(title: "One — Beginnings", paragraphs: longParagraphs),
      Chapter(title: "Two — The Turning", paragraphs: longParagraphs.reversed()),
      Chapter(title: "Three — After", paragraphs: longParagraphs),
    ]
  }
}

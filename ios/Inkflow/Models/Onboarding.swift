import Foundation
import SwiftData
import SwiftUI

/// What the reader wants out of ReadSync. Multi-select, drives copy in the reveal.
enum ReadingMotivation: String, CaseIterable, Identifiable {
  case finishMore = "Finish more books"
  case dailyHabit = "Build a daily habit"
  case listenOnGo = "Listen on the go"
  case classics = "Read the classics"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .finishMore: return "checkmark.seal"
    case .dailyHabit: return "flame"
    case .listenOnGo: return "headphones"
    case .classics: return "books.vertical"
    }
  }
}

/// How the reader likes to consume books — seeds the reading/listening split.
enum ConsumeMode: String, CaseIterable, Identifiable {
  case reading = "Read on the page"
  case listening = "Listen like an audiobook"
  case both = "Read and listen together"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .reading: return "book"
    case .listening: return "headphones"
    case .both: return "arrow.left.arrow.right"
    }
  }

  var detail: String {
    switch self {
    case .reading: return "A focused, Kindle-style reader"
    case .listening: return "Voice and speed controls for every book"
    case .both: return "Spoken text stays highlighted as you follow"
    }
  }
}

/// A daily reading-minutes target offered in onboarding.
struct DailyGoalOption: Identifiable, Hashable {
  let minutes: Int
  let label: String
  let blurb: String
  var id: Int { minutes }

  var shortBlurb: String { blurb.components(separatedBy: " · ").first ?? blurb }

  static let all: [DailyGoalOption] = [
    .init(minutes: 10, label: "10 min", blurb: "Casual · a few pages"),
    .init(minutes: 20, label: "20 min", blurb: "Steady · a chapter a day"),
    .init(minutes: 30, label: "30 min", blurb: "Committed · real progress"),
    .init(minutes: 45, label: "45 min", blurb: "Serious · finish books fast"),
  ]
}

/// A single recommended book shown as a real cover. These are *suggestions* that
/// seed Search — we never auto-download. Cover art comes from Open Library's free
/// cover API keyed by ISBN, so the onboarding + Search show real book covers.
struct GenreBook: Hashable, Identifiable {
  let title: String
  let author: String
  let isbn: String

  var id: String { isbn }

  /// Real cover artwork from the Open Library covers API (no key required).
  var coverURL: URL? {
    URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg")
  }

  /// What we drop into the Search field when the user taps this recommendation.
  var searchQuery: String { title }
}

/// A reading genre with real, popular recommendations shown as covers. Picking a
/// genre tailors the empty-library prompt and the Search recommendations — it does
/// not seed or download anything.
struct ReadingGenre: Identifiable, Hashable {
  let id: String
  let name: String
  let icon: String
  let tint: UInt
  /// IDs of genres a reader of this one tends to also enjoy. Drives the
  /// "Readers also like" rails so e.g. self-help surfaces business + philosophy.
  let relatedIDs: [String]
  /// A deep pool of popular titles, shown with real cover art. We surface a
  /// shuffled slice each time so recommendations feel fresh on every visit.
  let pool: [GenreBook]

  /// A fresh, shuffled slice of this genre's pool.
  func recommendations(_ count: Int = 4) -> [GenreBook] {
    Array(pool.shuffled().prefix(count))
  }

  /// The related genres a reader of this one is likely to also enjoy.
  var related: [ReadingGenre] {
    relatedIDs.compactMap(ReadingGenre.named)
  }

  static let all: [ReadingGenre] = [
    ReadingGenre(
      id: "selfhelp", name: "Self-help", icon: "lightbulb", tint: 0xC2703D,
      relatedIDs: ["business", "philosophy"],
      pool: [
        .init(title: "Atomic Habits", author: "James Clear", isbn: "9780735211292"),
        .init(title: "The Power of Now", author: "Eckhart Tolle", isbn: "9781577314806"),
        .init(title: "Deep Work", author: "Cal Newport", isbn: "9781455586691"),
        .init(title: "Mindset", author: "Carol S. Dweck", isbn: "9780345472328"),
        .init(
          title: "The 7 Habits of Highly Effective People", author: "Stephen R. Covey",
          isbn: "9781451639619"),
        .init(
          title: "The Subtle Art of Not Giving a F*ck", author: "Mark Manson", isbn: "9780062457714"
        ),
        .init(title: "Can't Hurt Me", author: "David Goggins", isbn: "9781544512280"),
      ]),
    ReadingGenre(
      id: "business", name: "Business & money", icon: "chart.line.uptrend.xyaxis", tint: 0x0F5C5B,
      relatedIDs: ["selfhelp", "philosophy"],
      pool: [
        .init(title: "Rich Dad Poor Dad", author: "Robert T. Kiyosaki", isbn: "9781612680194"),
        .init(title: "Zero to One", author: "Peter Thiel", isbn: "9780804139298"),
        .init(title: "The Lean Startup", author: "Eric Ries", isbn: "9780307887894"),
        .init(title: "The Psychology of Money", author: "Morgan Housel", isbn: "9780857197689"),
        .init(title: "The Intelligent Investor", author: "Benjamin Graham", isbn: "9780060555665"),
        .init(title: "Good to Great", author: "Jim Collins", isbn: "9780066620992"),
        .init(
          title: "The Millionaire Next Door", author: "Thomas J. Stanley", isbn: "9781589795471"),
      ]),
    ReadingGenre(
      id: "fiction", name: "Classic fiction", icon: "books.vertical", tint: 0x7A1F3D,
      relatedIDs: ["mystery", "scifi"],
      pool: [
        .init(title: "The Great Gatsby", author: "F. Scott Fitzgerald", isbn: "9780743273565"),
        .init(title: "Pride and Prejudice", author: "Jane Austen", isbn: "9780141439518"),
        .init(title: "1984", author: "George Orwell", isbn: "9780451524935"),
        .init(title: "To Kill a Mockingbird", author: "Harper Lee", isbn: "9780061120084"),
        .init(title: "Jane Eyre", author: "Charlotte Brontë", isbn: "9780141441146"),
        .init(title: "The Catcher in the Rye", author: "J.D. Salinger", isbn: "9780316769488"),
        .init(title: "Wuthering Heights", author: "Emily Brontë", isbn: "9780141439556"),
      ]),
    ReadingGenre(
      id: "mystery", name: "Mystery & thriller", icon: "magnifyingglass", tint: 0x37314A,
      relatedIDs: ["fiction", "scifi"],
      pool: [
        .init(title: "Gone Girl", author: "Gillian Flynn", isbn: "9780307588371"),
        .init(title: "The Silent Patient", author: "Alex Michaelides", isbn: "9781250301697"),
        .init(
          title: "The Girl with the Dragon Tattoo", author: "Stieg Larsson", isbn: "9780307454546"),
        .init(
          title: "The Hound of the Baskervilles", author: "Arthur Conan Doyle",
          isbn: "9780141034256"),
        .init(title: "And Then There Were None", author: "Agatha Christie", isbn: "9780062073488"),
        .init(title: "The Da Vinci Code", author: "Dan Brown", isbn: "9780307474278"),
        .init(title: "Big Little Lies", author: "Liane Moriarty", isbn: "9780425274866"),
      ]),
    ReadingGenre(
      id: "scifi", name: "Sci-fi & fantasy", icon: "sparkles", tint: 0x1F4F6E,
      relatedIDs: ["fiction", "mystery"],
      pool: [
        .init(title: "Dune", author: "Frank Herbert", isbn: "9780441013593"),
        .init(title: "The Hobbit", author: "J.R.R. Tolkien", isbn: "9780547928227"),
        .init(title: "Project Hail Mary", author: "Andy Weir", isbn: "9780593135204"),
        .init(title: "Frankenstein", author: "Mary Shelley", isbn: "9780141439471"),
        .init(title: "The Name of the Wind", author: "Patrick Rothfuss", isbn: "9780756404741"),
        .init(title: "Neuromancer", author: "William Gibson", isbn: "9780441569595"),
        .init(title: "A Game of Thrones", author: "George R. R. Martin", isbn: "9780553573404"),
      ]),
    ReadingGenre(
      id: "philosophy", name: "Philosophy", icon: "brain.head.profile", tint: 0x4A3B2A,
      relatedIDs: ["selfhelp", "business"],
      pool: [
        .init(title: "Meditations", author: "Marcus Aurelius", isbn: "9780140449334"),
        .init(title: "Man's Search for Meaning", author: "Viktor E. Frankl", isbn: "9780807014295"),
        .init(title: "The Art of War", author: "Sun Tzu", isbn: "9780140439199"),
        .init(title: "Beyond Good and Evil", author: "Friedrich Nietzsche", isbn: "9780140449235"),
        .init(title: "The Republic", author: "Plato", isbn: "9780140455113"),
        .init(title: "Letters from a Stoic", author: "Seneca", isbn: "9780140442106"),
        .init(
          title: "Thus Spoke Zarathustra", author: "Friedrich Nietzsche", isbn: "9780140441185"),
      ]),
  ]

  static func named(_ id: String) -> ReadingGenre? {
    all.first { $0.id == id }
  }
}

/// Captured answers from the onboarding quiz. A plain @Observable so each step can
/// bind into it; the final step turns it into a seeded goal + starter shelf.
@Observable
final class OnboardingState {
  var consumeMode: ConsumeMode = .both
  var dailyMinutes: Int = 20
  var genre: ReadingGenre = ReadingGenre.all[0]

  /// Weekly target derived from the daily goal (5 active days/week feels humane).
  var weeklyMinutes: Int { dailyMinutes * 5 }
}

/// Persists the "has finished onboarding" flag and the reader's chosen genre so
/// the Library + Search can keep recommending in their taste after onboarding.
enum OnboardingFlag {
  static let key = "readsync.didCompleteOnboarding"
  static let genreKey = "readsync.selectedGenre"

  static var completed: Bool {
    UserDefaults.standard.bool(forKey: key)
  }

  static func markCompleted() {
    UserDefaults.standard.set(true, forKey: key)
  }

  static var selectedGenre: ReadingGenre {
    let id = UserDefaults.standard.string(forKey: genreKey) ?? ""
    return ReadingGenre.named(id) ?? ReadingGenre.all[0]
  }

  static func saveGenre(_ genre: ReadingGenre) {
    UserDefaults.standard.set(genre.id, forKey: genreKey)
  }
}

/// Durable onboarding settings. `UserDefaults` remains a tiny launch-time cache
/// for the initial route, while this SwiftData model is the source of truth for
/// the reader's choices and the recommendation shelf that was presented.
@Model
final class ReaderProfile {
  @Attribute(.unique) var id: UUID
  var hasCompletedOnboarding: Bool
  var consumeModeRaw: String
  var dailyMinutesTarget: Int
  var weeklyMinutesTarget: Int
  var selectedGenreID: String
  /// Stable identifiers for the recommendations shown on the completion screen.
  /// Covers themselves are remote assets and are deliberately not duplicated in
  /// the local store; their ISBNs recreate the exact source metadata.
  var onboardingRecommendationISBNs: [String]
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    hasCompletedOnboarding: Bool = false,
    consumeModeRaw: String = ConsumeMode.both.rawValue,
    dailyMinutesTarget: Int = 20,
    weeklyMinutesTarget: Int = 100,
    selectedGenreID: String = ReadingGenre.all[0].id,
    onboardingRecommendationISBNs: [String] = [],
    updatedAt: Date = .now
  ) {
    self.id = id
    self.hasCompletedOnboarding = hasCompletedOnboarding
    self.consumeModeRaw = consumeModeRaw
    self.dailyMinutesTarget = dailyMinutesTarget
    self.weeklyMinutesTarget = weeklyMinutesTarget
    self.selectedGenreID = selectedGenreID
    self.onboardingRecommendationISBNs = onboardingRecommendationISBNs
    self.updatedAt = updatedAt
  }

  var consumeMode: ConsumeMode {
    ConsumeMode(rawValue: consumeModeRaw) ?? .both
  }

  var selectedGenre: ReadingGenre {
    ReadingGenre.named(selectedGenreID) ?? ReadingGenre.all[0]
  }
}

enum OnboardingPersistence {
  /// Upserts the single reader profile and reading goal together. This is
  /// deliberately synchronous so completion is never acknowledged before the
  /// user-visible setup is on disk.
  @MainActor
  static func save(
    state: OnboardingState,
    recommendations: [GenreBook],
    profiles: [ReaderProfile],
    goals: [ReadingGoal],
    in context: ModelContext
  ) throws {
    let profile: ReaderProfile
    if let existing = profiles.first {
      profile = existing
    } else {
      profile = ReaderProfile()
      context.insert(profile)
    }

    profile.hasCompletedOnboarding = true
    profile.consumeModeRaw = state.consumeMode.rawValue
    profile.dailyMinutesTarget = state.dailyMinutes
    profile.weeklyMinutesTarget = state.weeklyMinutes
    profile.selectedGenreID = state.genre.id
    profile.onboardingRecommendationISBNs = recommendations.map(\.isbn)
    profile.updatedAt = .now

    let goal: ReadingGoal
    if let existing = goals.first {
      goal = existing
    } else {
      goal = ReadingGoal()
      context.insert(goal)
    }
    goal.dailyMinutesTarget = state.dailyMinutes
    goal.weeklyMinutesTarget = state.weeklyMinutes

    try context.save()
  }

  /// Imports an existing app's lightweight UserDefaults state into SwiftData.
  /// This protects people upgrading from a build made before `ReaderProfile`.
  @MainActor
  static func migrateLegacyState(in context: ModelContext) {
    let profiles = (try? context.fetch(FetchDescriptor<ReaderProfile>())) ?? []
    guard profiles.isEmpty else {
      if let profile = profiles.first, profile.hasCompletedOnboarding {
        OnboardingFlag.saveGenre(profile.selectedGenre)
        OnboardingFlag.markCompleted()
      }
      return
    }

    guard OnboardingFlag.completed else { return }
    let genre = OnboardingFlag.selectedGenre
    let profile = ReaderProfile(
      hasCompletedOnboarding: true,
      selectedGenreID: genre.id
    )
    context.insert(profile)
    try? context.save()
  }
}

/// Lightweight cross-tab router so one screen can jump to another tab with a
/// pre-filled search query (e.g. the empty library → Search a genre).
@Observable
final class AppRouter {
  /// 0 Library · 1 Search · 2 You · 3 Notebook — matches the TabView order.
  var selectedTab: Int = 0
  /// A query to drop into Search the next time it appears.
  var pendingSearch: String?

  func openSearch(query: String? = nil) {
    pendingSearch = query
    selectedTab = 1
  }
}

extension EnvironmentValues {
  @Entry var appRouter: AppRouter = AppRouter()
}

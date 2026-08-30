import SwiftData
import SwiftUI

@main
struct InkflowApp: App {
  let container: ModelContainer
  /// These shared observable instances must be injected at the scene root.
  /// Keeping the injection outside `ContentView` means lazily-created TabView
  /// children (notably Stats) cannot be evaluated before AuthStore is present.
  @State private var auth = AuthStore()
  @State private var router = AppRouter()

  init() {
    let schema = Schema([
      Book.self, Highlight.self, Note.self,
      ReadingSession.self, ReadingGoal.self, ReaderProfile.self,
    ])
    container = Self.makeContainer(schema: schema)
    Self.purgeSampleBooks(container.mainContext)
    Self.seedIfNeeded(container.mainContext)
    OnboardingPersistence.migrateLegacyState(in: container.mainContext)
  }

  /// Creates the model container without ever deleting a reader's local data.
  /// On a fresh iOS 26 simulator the Application Support directory is not
  /// guaranteed to exist yet, so create its parent before SwiftData opens the
  /// default store. Additive model changes (such as `ReaderProfile`) then use
  /// SwiftData's normal lightweight migration path.
  private static func makeContainer(schema: Schema) -> ModelContainer {
    let config = ModelConfiguration(schema: schema)
    let storeDirectory = config.url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: storeDirectory, withIntermediateDirectories: true)
      return try ModelContainer(for: schema, configurations: [config])
    } catch {
      fatalError("Failed to open the local reading library without data loss: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(auth)
        .environment(\.appRouter, router)
    }
    .modelContainer(container)
  }

  /// One-time cleanup: remove any leftover placeholder books persisted by an
  /// earlier build that seeded a sample library. Real downloads/imports always
  /// set `isDownloaded = true` and a non-empty `sourceIdentifier`; anything
  /// missing both is stale sample data. We fetch everything and filter in Swift
  /// because SwiftData string-empty predicates are unreliable across versions.
  @MainActor
  static func purgeSampleBooks(_ context: ModelContext) {
    guard let all = try? context.fetch(FetchDescriptor<Book>()) else { return }
    let stale = all.filter { !$0.isDownloaded && $0.sourceIdentifier.isEmpty }
    guard !stale.isEmpty else { return }
    for book in stale { context.delete(book) }
    try? context.save()
  }

  /// Seed only the reading goal on first launch. Books come from real downloads
  /// in Discover — no sample/placeholder books.
  @MainActor
  static func seedIfNeeded(_ context: ModelContext) {
    let goalCount = (try? context.fetchCount(FetchDescriptor<ReadingGoal>())) ?? 0
    guard goalCount == 0 else { return }
    context.insert(SampleLibrary.makeGoal())
    try? context.save()
  }
}

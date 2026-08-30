import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var didOnboard = OnboardingFlag.completed
  @Environment(\.appRouter) private var router
  @Query private var books: [Book]
  @Query(sort: \Highlight.createdDate, order: .reverse) private var highlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var notes: [Note]
  @Query(sort: \ReadingSession.date, order: .reverse) private var sessions: [ReadingSession]
  @AppStorage("digest.email") private var digestEmail = ""
  @AppStorage("digest.daily-enabled") private var dailyDigestEnabled = false
  @AppStorage("digest.weekly-enabled") private var weeklyDigestEnabled = false

  init() {
    UITabBar.appearance().tintColor = UIColor(Theme.accent)
  }

  var body: some View {
    Group {
      if didOnboard && !router.isReplayingOnboarding {
        mainTabs
      } else {
        OnboardingView {
          withAnimation(.smooth) {
            didOnboard = true
            router.isReplayingOnboarding = false
          }
        }
      }
    }
    .task(id: digestSyncFingerprint) {
      guard didOnboard, dailyDigestEnabled || weeklyDigestEnabled,
        digestEmail.contains("@")
      else { return }
      // A finished reading/listening session, saved idea, or library change
      // refreshes the server-side recap mirror without blocking navigation.
      try? await DigestSync.sync(
        highlights: highlights, notes: notes, books: books, sessions: sessions)
    }
    .__tenxTrackView("ContentView")
  }

  private var digestSyncFingerprint: String {
    let latestSession = sessions.first?.date.timeIntervalSince1970 ?? 0
    let latestHighlight = highlights.first?.createdDate.timeIntervalSince1970 ?? 0
    let latestNote = notes.first?.createdDate.timeIntervalSince1970 ?? 0
    return "\(books.count):\(sessions.count):\(latestSession):\(latestHighlight):\(latestNote)"
  }

  private var mainTabs: some View {
    @Bindable var bindableRouter = router
    return Group {
      TabView(selection: $bindableRouter.selectedTab) {
        LibraryView()
          .tabItem { Label("Library", systemImage: "books.vertical.fill") }
          .tag(0)

        SearchView()
          .tabItem { Label("Search", systemImage: "magnifyingglass") }
          .tag(1)

        NotebookView()
          .tabItem { Label("Notes", systemImage: "bookmark.fill") }
          .tag(2)

        StatsView()
          .tabItem { Label("You", systemImage: "person.fill") }
          .tag(3)
      }
      .tint(Theme.accent)
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(PreviewData.container)
    .environment(AuthStore())
    .environment(\.appRouter, AppRouter())
}

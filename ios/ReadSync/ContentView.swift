import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var didOnboard = OnboardingFlag.completed
  @Environment(\.appRouter) private var router

  init() {
    UITabBar.appearance().tintColor = UIColor(Theme.accent)
  }

  var body: some View {
    Group {
      if didOnboard {
        mainTabs
      } else {
        OnboardingView {
          withAnimation(.smooth) { didOnboard = true }
        }
      }
    }
    .__tenxTrackView("ContentView")
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

        StatsView()
          .tabItem { Label("You", systemImage: "person.fill") }
          .tag(2)

        NotebookView()
          .tabItem { Label("Notebook", systemImage: "bookmark.fill") }
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

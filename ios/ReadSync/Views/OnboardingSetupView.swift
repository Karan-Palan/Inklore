import SwiftData
import SwiftUI

/// Personalized reveal. Persists the lightweight choices and hands the reader
/// directly to a real source—never an auth screen or paywall.
struct OnboardingSetupView: View {
  let state: OnboardingState
  var onFinish: () -> Void

  @Environment(\.modelContext) private var context
  @Environment(\.appRouter) private var router
  @Query private var goals: [ReadingGoal]
  @Query private var profiles: [ReaderProfile]

  @State private var revealed = false

  @State private var recommendations: [GenreBook] = []
  @State private var persistenceError: String?

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.paper, Theme.accentSoft.opacity(0.5)],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: Theme.lg) {
        Spacer(minLength: Theme.lg)

        VStack(spacing: Theme.sm) {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .symbolEffect(.bounce, value: revealed)

          Text("Your shelf is ready")
            .font(.system(.title2, design: .serif).weight(.bold))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)

          Text("\(state.consumeMode.rawValue) · \(state.dailyMinutes) min a day")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.inkSoft)
        }

        VStack(alignment: .leading, spacing: Theme.md) {
          Text("POPULAR IN \(state.genre.name.uppercased())")
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(Theme.inkFaint)

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.md) {
              ForEach(recommendations) { rec in
                VStack(spacing: 6) {
                  GenreCoverThumb(url: rec.coverURL, tint: state.genre.tint, width: 92)
                  Text(rec.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16)
              }
            }
            .padding(.horizontal, 2)
          }

          Text("Start with a free download, or open Library and tap ＋ to import your own PDF, EPUB, or Word document.")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(Theme.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Theme.surface.opacity(0.85),
          in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
        )
        .padding(.horizontal, Theme.lg)

        Spacer()

        VStack(spacing: Theme.sm) {
          OnboardingPrimaryButton(title: "Explore free books") {
            completeOnboarding {
              router.openSearch(query: recommendations.first?.searchQuery)
            }
          }
          Button {
            completeOnboarding { router.selectedTab = 0 }
          } label: {
            Label("Open my library", systemImage: "square.and.arrow.down")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.inkSoft)
              .frame(minHeight: 44)
          }
          if let persistenceError {
            Text(persistenceError)
              .font(.footnote)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, Theme.xl)
        .padding(.bottom, Theme.lg)
      }
    }
    .task { await applyPlan() }
    .__tenxTrackView("OnboardingSetupView")
  }

  @MainActor
  private func applyPlan() async {
    recommendations = state.genre.recommendations(4)
    withAnimation(.smooth(duration: 0.5)) { revealed = true }
  }

  @MainActor
  private func completeOnboarding(destination: () -> Void) {
    let displayedRecommendations = recommendations.isEmpty
      ? state.genre.recommendations(4)
      : recommendations
    do {
      try OnboardingPersistence.save(
        state: state,
        recommendations: displayedRecommendations,
        profiles: profiles,
        goals: goals,
        in: context
      )
      OnboardingFlag.saveGenre(state.genre)
      OnboardingFlag.markCompleted()
      destination()
      onFinish()
    } catch {
      persistenceError = "We couldn't save your reading plan. Please try again."
      TenXPreviewSupport.log("onboarding persistence failed: \(error.localizedDescription)")
    }
  }
}

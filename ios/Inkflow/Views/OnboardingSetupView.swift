import SwiftData
import SwiftUI

/// Personalized plan reveal and starter-shelf preparation. Choices are written
/// before any network work begins, so a slow connection never loses the plan.
struct OnboardingSetupView: View {
  private enum PreparedShelfDestination: Equatable {
    case library
    case search
  }

  let state: OnboardingState
  var onFinish: () -> Void

  @Environment(\.modelContext) private var context
  @Environment(\.appRouter) private var router
  @Query private var goals: [ReadingGoal]
  @Query private var profiles: [ReaderProfile]
  @Query private var library: [Book]

  @State private var revealed = false
  @State private var recommendations: [GenreBook] = []
  @State private var persistenceError: String?
  @State private var isPreparingShelf = false
  @State private var preparedBookCount = 0
  @State private var preparationStatus = ""
  @State private var preparationFailures: [String] = []
  @State private var shelfPreparationFinished = false
  @State private var preparedShelfDestination: PreparedShelfDestination = .library

  private var starterBooks: [GutenbergStarterBook] {
    state.genre.starterBooks
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.paper, Theme.mossSoft.opacity(0.55), Theme.accentSoft.opacity(0.3)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      Circle()
        .fill(Theme.sun.opacity(0.24))
        .frame(width: 210, height: 210)
        .blur(radius: 8)
        .offset(x: 145, y: -320)
        .accessibilityHidden(true)

      if isPreparingShelf || shelfPreparationFinished {
        shelfPreparationView
      } else {
        planReveal
      }
    }
    .task { await applyPlan() }
    .__tenxTrackView("OnboardingSetupView")
  }

  private var planReveal: some View {
    VStack(spacing: Theme.xl) {
      Spacer(minLength: Theme.sm)

      VStack(spacing: Theme.sm) {
        ZStack {
          Circle()
            .fill(Theme.moss)
            .frame(width: 68, height: 68)
          Image(systemName: "checkmark")
            .font(.title2.weight(.black))
            .foregroundStyle(.white)
        }
        .shadow(color: Theme.moss.opacity(0.22), radius: 15, y: 8)
        .symbolEffect(.bounce, value: revealed)

        Text("Your reading plan is ready")
          .font(.system(.title2, design: .serif).weight(.bold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)

        Text("A small rhythm, built around how you actually like to read.")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Theme.inkSoft)
          .multilineTextAlignment(.center)
      }

      planCard
      starterShelfCard

      Spacer()

      VStack(spacing: Theme.sm) {
        OnboardingPrimaryButton(title: "Prepare my 2-book shelf") {
          startShelfPreparation(destination: .library)
        }
        Button {
          startShelfPreparation(destination: .search)
        } label: {
          Label("Prepare shelf & explore free books", systemImage: "magnifyingglass")
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

  private var planCard: some View {
    HStack(spacing: Theme.lg) {
      ZStack {
        Circle()
          .fill(Theme.accentSoft)
          .frame(width: 58, height: 58)
        VStack(spacing: 0) {
          Text("\(state.dailyMinutes)")
            .font(.title3.monospacedDigit().weight(.black))
          Text("MIN")
            .font(.caption2.weight(.heavy))
            .tracking(0.7)
        }
        .foregroundStyle(Theme.accentDeep)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Your daily chapter")
          .font(.headline.weight(.bold))
          .foregroundStyle(Theme.ink)
        Text("\(state.weeklyMinutes) mindful minutes a week · \(state.consumeMode.rawValue)")
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
    .padding(.horizontal, Theme.lg)
    .accessibilityElement(children: .combine)
  }

  private var starterShelfCard: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("YOUR PUBLIC-DOMAIN STARTER SHELF")
            .font(.caption2.weight(.heavy))
            .tracking(1.1)
            .foregroundStyle(Theme.inkFaint)
          Text("Two full EPUBs, selected for your \(state.genre.name.lowercased()) mood")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
        }
        Spacer(minLength: Theme.sm)
        Image(systemName: state.genre.icon)
          .font(.headline.weight(.bold))
          .foregroundStyle(Color(hex: state.genre.tint))
          .accessibilityHidden(true)
      }

      HStack(alignment: .top, spacing: Theme.lg) {
        ForEach(starterBooks) { starter in
          VStack(alignment: .leading, spacing: Theme.sm) {
            GenreCoverThumb(url: starter.coverURL, tint: state.genre.tint, width: 86)
            Text(starter.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(Theme.ink)
              .lineLimit(2)
              .frame(width: 86, alignment: .leading)
            Text(starter.author)
              .font(.caption2)
              .foregroundStyle(Theme.inkFaint)
              .lineLimit(1)
              .frame(width: 86, alignment: .leading)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(starter.title) by \(starter.author), public-domain EPUB from Project Gutenberg")
        }
      }

      Label("Legal public-domain EPUBs from Project Gutenberg", systemImage: "checkmark.shield.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.moss)
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
    .shadow(color: Theme.shadow.opacity(0.34), radius: 16, y: 7)
    .padding(.horizontal, Theme.lg)
  }

  private var shelfPreparationView: some View {
    VStack(spacing: Theme.xl) {
      Spacer()

      ZStack {
        Circle()
          .fill(isPreparingShelf ? Theme.accentSoft : (preparationFailures.isEmpty ? Theme.mossSoft : Theme.accentSoft))
          .frame(width: 84, height: 84)
        if isPreparingShelf {
          ProgressView()
            .controlSize(.large)
            .tint(Theme.accent)
        } else {
          Image(systemName: preparationFailures.isEmpty ? "checkmark" : "exclamationmark")
            .font(.title.weight(.black))
            .foregroundStyle(preparationFailures.isEmpty ? Theme.moss : Theme.accentDeep)
        }
      }
      .accessibilityHidden(true)

      VStack(spacing: Theme.sm) {
        Text(isPreparingShelf ? "Preparing your first shelf" : preparationTitle)
          .font(.system(.title2, design: .serif).weight(.bold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)
        Text(preparationStatus)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Theme.inkSoft)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Theme.xl)
      }

      VStack(alignment: .leading, spacing: Theme.sm) {
        HStack {
          Text("EPUB PREPARATION")
            .font(.caption2.weight(.heavy))
            .tracking(1.1)
            .foregroundStyle(Theme.inkFaint)
          Spacer()
          Text("\(preparedBookCount) of \(starterBooks.count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(Theme.accentDeep)
        }
        ProgressView(value: Double(preparedBookCount), total: Double(max(starterBooks.count, 1)))
          .tint(Theme.accent)
          .accessibilityLabel("Starter shelf preparation, \(preparedBookCount) of \(starterBooks.count) books")
      }
      .padding(Theme.lg)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(Theme.hairline, lineWidth: 1)
      }
      .padding(.horizontal, Theme.lg)

      if !preparationFailures.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("Couldn’t prepare")
            .font(.caption.weight(.heavy))
            .foregroundStyle(Theme.accentDeep)
          Text(preparationFailures.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.xl)
      }

      if let persistenceError {
        Text(persistenceError)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Theme.xl)
      }

      Spacer()

      if !isPreparingShelf {
        VStack(spacing: Theme.sm) {
          if preparationFailures.isEmpty {
            OnboardingPrimaryButton(
              title: preparedShelfDestination == .library ? "Open my shelf" : "Explore free books"
            ) {
              openPreparedShelfDestination()
            }
          } else {
            OnboardingPrimaryButton(title: "Try again") {
              startShelfPreparation(destination: preparedShelfDestination)
            }
            Button("Open my library anyway") {
              openLibrary()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.inkSoft)
            .frame(minHeight: 44)
          }
        }
        .padding(.horizontal, Theme.xl)
        .padding(.bottom, Theme.lg)
      } else {
        Text("Downloads are saved locally and ready to read offline.")
          .font(.footnote)
          .foregroundStyle(Theme.inkFaint)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Theme.xl)
          .padding(.bottom, Theme.lg)
      }
    }
  }

  private var preparationTitle: String {
    preparationFailures.isEmpty ? "Your first shelf is ready" : "Your plan is saved"
  }

  @MainActor
  private func applyPlan() async {
    recommendations = state.genre.recommendations(4)
    withAnimation(.smooth(duration: 0.5)) { revealed = true }
  }

  @MainActor
  private func startShelfPreparation(destination: PreparedShelfDestination) {
    guard !isPreparingShelf, saveOnboardingChoices() else { return }

    preparedShelfDestination = destination
    isPreparingShelf = true
    shelfPreparationFinished = false
    preparedBookCount = 0
    preparationFailures = []
    preparationStatus = "Finding your first public-domain EPUB…"

    Task { @MainActor in
      await prepareStarterShelf()
    }
  }

  @MainActor
  private func prepareStarterShelf() async {
    let starters = starterBooks
    var knownIdentifiers = Set(library.map(\.sourceIdentifier).filter { !$0.isEmpty })

    for starter in starters {
      if knownIdentifiers.contains(starter.sourceIdentifier) {
        preparedBookCount += 1
        preparationStatus = "\(starter.title) is already on your shelf."
        continue
      }

      preparationStatus = "Downloading \(starter.title)…"
      do {
        let book = try await BookDownloader.download(starter.discoverResult, into: context)
        book.category = state.genre.name
        try context.save()
        knownIdentifiers.insert(starter.sourceIdentifier)
      } catch {
        preparationFailures.append(starter.title)
        TenXPreviewSupport.log("starter shelf download failed for \(starter.gutenbergID): \(error.localizedDescription)")
      }
      preparedBookCount += 1
    }

    isPreparingShelf = false
    shelfPreparationFinished = true
    if preparationFailures.isEmpty {
      preparationStatus = "Both EPUBs are downloaded, extracted, and ready whenever you are."
    } else if preparationFailures.count == starters.count {
      preparationStatus = "We couldn’t reach Project Gutenberg just now. Your reading plan is still saved."
    } else {
      preparationStatus = "Part of your shelf is ready. You can retry the remaining EPUB whenever you like."
    }
  }

  @MainActor
  private func saveOnboardingChoices() -> Bool {
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
      persistenceError = nil
      return true
    } catch {
      persistenceError = "We couldn't save your reading plan. Please try again."
      TenXPreviewSupport.log("onboarding persistence failed: \(error.localizedDescription)")
      return false
    }
  }

  @MainActor
  private func openLibrary() {
    // Do not skip onboarding on a relaunch until shelf preparation has either
    // finished or the reader has explicitly chosen to continue after an error.
    guard finalizeOnboarding() else { return }
    router.selectedTab = 0
    onFinish()
  }

  @MainActor
  private func openPreparedShelfDestination() {
    if preparedShelfDestination == .search {
      guard finalizeOnboarding() else { return }
      router.openSearch(query: state.genre.name)
      onFinish()
    } else {
      openLibrary()
    }
  }

  @MainActor
  private func finalizeOnboarding() -> Bool {
    do {
      try OnboardingPersistence.finalizeOnboarding(in: context)
      persistenceError = nil
      return true
    } catch {
      persistenceError = "We couldn't finish saving your shelf. Please try again."
      TenXPreviewSupport.log("onboarding finalization failed: \(error.localizedDescription)")
      return false
    }
  }
}

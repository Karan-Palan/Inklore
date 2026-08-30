import SwiftUI

/// Product education and lightweight personalization steps.

// MARK: - Sources

struct SourcesStep: View {
  var progress: Double
  var stepLabel: String
  var onBack: () -> Void
  var onNext: () -> Void

  var body: some View {
    OnboardingScaffold(
      progress: progress,
      stepLabel: stepLabel,
      title: "Start with any book",
      subtitle: "Your shelf can begin online or with a file you already own.",
      ctaTitle: "Continue",
      onBack: onBack,
      onContinue: onNext
    ) {
      VStack(spacing: Theme.md) {
        OnboardingCapabilityCard(
          icon: "building.columns.fill",
          title: "Search free libraries",
          detail: "Discover downloadable books from the Internet Archive and Project Gutenberg.",
          tint: Color(hex: 0x0F5C5B))
        OnboardingCapabilityCard(
          icon: "doc.richtext.fill",
          title: "Import your own files",
          detail: "Open PDF, EPUB, and Word documents directly from Files.",
          tint: Color(hex: 0x2E5E9E))
        OnboardingCapabilityCard(
          icon: "link",
          title: "Bring a direct link",
          detail: "Paste a PDF or EPUB link and keep it beside the rest of your library.",
          tint: Color(hex: 0x7A1F3D))

        Label("Your imported books stay on this device.", systemImage: "lock.fill")
          .font(.footnote.weight(.medium))
          .foregroundStyle(Theme.inkSoft)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, Theme.sm)
      }
    }
  }
}

// MARK: - Preferences

struct PreferencesStep: View {
  @Bindable var state: OnboardingState
  var progress: Double
  var stepLabel: String
  var onBack: () -> Void
  var onNext: () -> Void

  var body: some View {
    OnboardingScaffold(
      progress: progress,
      stepLabel: stepLabel,
      title: "How should ReadSync fit your day?",
      subtitle: "You can switch between page and audio at any time.",
      ctaTitle: "Continue",
      onBack: onBack,
      onContinue: onNext
    ) {
      VStack(alignment: .leading, spacing: Theme.lg) {
        Text("I'LL MOSTLY")
          .font(.caption.weight(.bold))
          .tracking(1.1)
          .foregroundStyle(Theme.inkFaint)

        VStack(spacing: Theme.md) {
          ForEach(ConsumeMode.allCases) { mode in
            OnboardingOptionRow(
              icon: mode.icon, title: mode.rawValue, subtitle: mode.detail,
              selected: state.consumeMode == mode
            ) {
              state.consumeMode = mode
            }
          }
        }

        Text("MY DAILY RHYTHM")
          .font(.caption.weight(.bold))
          .tracking(1.1)
          .foregroundStyle(Theme.inkFaint)
          .padding(.top, Theme.sm)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Theme.sm) {
            ForEach(DailyGoalOption.all) { option in
              GoalChip(
                option: option,
                selected: state.dailyMinutes == option.minutes
              ) {
                state.dailyMinutes = option.minutes
              }
            }
          }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
      }
    }
  }
}

private struct GoalChip: View {
  let option: DailyGoalOption
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 3) {
        Text(option.label)
          .font(.headline.monospacedDigit())
        Text(option.shortBlurb)
          .font(.caption)
      }
      .foregroundStyle(selected ? Color.white : Theme.ink)
      .frame(width: 104, alignment: .leading)
      .frame(minHeight: 62, alignment: .leading)
      .padding(.horizontal, Theme.md)
      .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - Genre

struct GenreStep: View {
  @Bindable var state: OnboardingState
  var progress: Double
  var stepLabel: String
  var onBack: () -> Void
  var onNext: () -> Void

  private let columns = [
    GridItem(.flexible(), spacing: Theme.md), GridItem(.flexible(), spacing: Theme.md),
  ]

  var body: some View {
    OnboardingScaffold(
      progress: progress,
      stepLabel: stepLabel,
      title: "What do you love to read?",
      subtitle:
        "Pick one for your first recommendations. You can search for anything later.",
      ctaTitle: "Continue",
      onBack: onBack,
      onContinue: onNext
    ) {
      LazyVGrid(columns: columns, spacing: Theme.md) {
        ForEach(ReadingGenre.all) { genre in
          GenreCard(genre: genre, selected: state.genre == genre) {
            state.genre = genre
          }
        }
      }
    }
  }
}

private struct GenreCard: View {
  let genre: ReadingGenre
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: Theme.sm) {
        HStack(spacing: Theme.sm) {
          Image(systemName: genre.icon)
            .font(.headline)
            .foregroundStyle(selected ? .white : Color(hex: genre.tint))
            .frame(width: 38, height: 38)
            .background(
              selected ? Color(hex: genre.tint) : Color(hex: genre.tint).opacity(0.14),
              in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
            )
          Spacer(minLength: 0)
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(Color(hex: genre.tint))
          }
        }

        // Real cover art preview of the genre's top recommendations.
        HStack(spacing: -14) {
          ForEach(Array(genre.pool.prefix(3))) { rec in
            GenreCoverThumb(url: rec.coverURL, tint: genre.tint)
          }
        }
        .padding(.vertical, 2)

        Text(genre.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
      .padding(Theme.md)
      .background(
        Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? Color(hex: genre.tint) : Theme.hairline, lineWidth: selected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .animation(.snappy, value: selected)
  }
}

/// A small real book-cover thumbnail with a tasteful gradient fallback while the
/// Open Library image loads (or if it's missing).
struct GenreCoverThumb: View {
  let url: URL?
  var tint: UInt = 0x37314A
  var width: CGFloat = 40

  private var height: CGFloat { width * 1.5 }

  var body: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color(hex: tint).opacity(0.85), Color(hex: tint).opacity(0.45)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .frame(width: width, height: height)
      .overlay {
        if let url {
          AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
              image.resizable().scaledToFill()
            } else if case .empty = phase {
              ProgressView().controlSize(.mini).tint(.white)
            } else {
              Image(systemName: "book.closed.fill")
                .font(.system(size: width * 0.32))
                .foregroundStyle(.white.opacity(0.8))
            }
          }
          .frame(width: width, height: height)
          .clipped()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(.white.opacity(0.6), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
  }
}

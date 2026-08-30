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
        HStack(spacing: Theme.sm) {
          Image(systemName: "tray.full.fill")
            .foregroundStyle(Theme.accent)
          Text("ONE CALM HOME FOR EVERY FORMAT")
            .font(.caption2.weight(.heavy))
            .tracking(1)
            .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.xs)

        OnboardingCapabilityCard(
          icon: "building.columns.fill",
          title: "Find a book with a past",
          detail: "Discover downloadable books from the Internet Archive and Project Gutenberg.",
          tint: Color(adaptiveAccentHex: 0x0F5C5B))
        OnboardingCapabilityCard(
          icon: "doc.richtext.fill",
          title: "Bring the books you own",
          detail: "Open PDF, EPUB, and Word documents directly from Files.",
          tint: Color(adaptiveAccentHex: 0x2E5E9E))
        OnboardingCapabilityCard(
          icon: "link",
          title: "Save a good link",
          detail: "Paste a PDF or EPUB link and keep it beside the rest of your library.",
          tint: Color(adaptiveAccentHex: 0x7A1F3D))

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
      title: "How should Inkflow fit your day?",
      subtitle: "You can switch between page and audio at any time.",
      ctaTitle: "Continue",
      onBack: onBack,
      onContinue: onNext
    ) {
      VStack(alignment: .leading, spacing: Theme.lg) {
        OnboardingSectionLabel("HOW YOU'LL SPEND TIME HERE")

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

        OnboardingSectionLabel("YOUR DAILY RHYTHM")
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
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(option.label)
            .font(.headline.monospacedDigit().weight(.bold))
          Spacer(minLength: 0)
          if selected {
            Image(systemName: "checkmark")
              .font(.caption.weight(.black))
          }
        }
        Text(option.shortBlurb)
          .font(.caption.weight(.medium))
      }
      .foregroundStyle(selected ? Color.white : Theme.ink)
      .frame(width: 104, alignment: .leading)
      .frame(minHeight: 68, alignment: .leading)
      .padding(.horizontal, Theme.md)
      .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .animation(.snappy, value: selected)
    .sensoryFeedback(.selection, trigger: selected)
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
      VStack(alignment: .leading, spacing: Theme.md) {
        HStack(spacing: Theme.sm) {
          Image(systemName: "wand.and.stars")
            .foregroundStyle(Theme.accent)
          Text("WE'LL BUILD YOUR FIRST SHELF AROUND THIS")
            .font(.caption2.weight(.heavy))
            .tracking(1)
            .foregroundStyle(Theme.inkFaint)
        }

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
}

private struct GenreCard: View {
  let genre: ReadingGenre
  let selected: Bool
  let action: () -> Void

  private var tint: Color { Color(adaptiveAccentHex: genre.tint) }

  var body: some View {
    Button(action: action) {
      VStack(spacing: Theme.sm) {
        ZStack(alignment: .topTrailing) {
          Image(systemName: genre.icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(selected ? .white : tint)
            .frame(width: 46, height: 46)
            .background(
              selected ? tint : tint.opacity(0.14),
              in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
            )
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.bold))
            .foregroundStyle(selected ? tint : Theme.inkFaint.opacity(0.4))
            .background(Theme.surface, in: Circle())
            .offset(x: 8, y: -7)
        }

        // Real cover art preview of the genre's top recommendations.
        HStack(spacing: -14) {
          ForEach(Array(genre.pool.prefix(3))) { rec in
            GenreCoverThumb(url: rec.coverURL, tint: genre.tint)
          }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)

        Text(genre.name)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
      .padding(Theme.md)
      .background(
        selected ? tint.opacity(0.08) : Theme.surface,
        in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? tint : Theme.hairline, lineWidth: selected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .animation(.snappy, value: selected)
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct OnboardingSectionLabel: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    HStack(spacing: Theme.sm) {
      Capsule()
        .fill(Theme.accent)
        .frame(width: 18, height: 3)
      Text(title)
        .font(.caption2.weight(.heavy))
        .tracking(1.1)
        .foregroundStyle(Theme.inkFaint)
    }
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

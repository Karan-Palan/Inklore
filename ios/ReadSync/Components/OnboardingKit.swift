import SwiftUI

/// Shared building blocks for the onboarding flow so every step has the same
/// rhythm: a thin progress bar, a generous headline block, scrollable content,
/// and a pinned primary action. Keeps the step screens themselves tiny.

/// Page scaffold: progress bar + title/subtitle header + content + bottom CTA.
struct OnboardingScaffold<Content: View>: View {
  var progress: Double
  var stepLabel: String?
  var title: String
  var subtitle: String?
  var ctaTitle: String
  var ctaEnabled: Bool = true
  var onBack: (() -> Void)?
  var onContinue: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        content
          .padding(.horizontal, Theme.xl)
          .padding(.top, Theme.lg)
          .padding(.bottom, Theme.xxl)
      }
      .scrollBounceBehavior(.basedOnSize)
      footer
    }
    .background(Theme.paper)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      HStack(spacing: Theme.md) {
        if let onBack {
          Button(action: onBack) {
            Image(systemName: "chevron.left")
              .font(.headline.weight(.semibold))
              .foregroundStyle(Theme.inkSoft)
              .frame(width: 44, height: 44)
              .background(Theme.surfaceAlt, in: Circle())
          }
          .accessibilityLabel("Go back")
        }
        OnboardingProgressBar(progress: progress)
        if let stepLabel {
          Text(stepLabel)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.inkFaint)
            .accessibilityHidden(true)
        }
      }

      VStack(alignment: .leading, spacing: Theme.sm) {
        Text(title)
          .font(.system(.largeTitle, design: .serif).weight(.bold))
          .foregroundStyle(Theme.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.horizontal, Theme.xl)
    .padding(.top, Theme.md)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Divider().background(Theme.hairline)
      OnboardingPrimaryButton(title: ctaTitle, enabled: ctaEnabled, action: onContinue)
        .padding(.horizontal, Theme.xl)
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
    }
    .background(Theme.paper)
  }
}

/// Thin terracotta progress bar.
struct OnboardingProgressBar: View {
  var progress: Double

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.surfaceAlt)
        Capsule()
          .fill(Theme.accent)
          .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
          .animation(.snappy, value: progress)
      }
    }
    .frame(height: 6)
  }
}

/// Full-width primary CTA used at the bottom of every step.
struct OnboardingPrimaryButton: View {
  var title: String
  var enabled: Bool = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .padding(.horizontal, Theme.lg)
        .background(enabled ? Theme.accent : Theme.inkFaint, in: Capsule())
    }
    .disabled(!enabled)
    .animation(.snappy, value: enabled)
  }
}

/// A selectable option row with an icon, title, optional subtitle, and check state.
struct OnboardingOptionRow: View {
  var icon: String
  var title: String
  var subtitle: String?
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.md) {
        Image(systemName: icon)
          .font(.headline)
          .foregroundStyle(selected ? .white : Theme.accent)
          .frame(width: 44, height: 44)
          .background(
            selected ? Theme.accent : Theme.accentSoft.opacity(0.55),
            in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
          )

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
          if let subtitle {
            Text(subtitle)
              .font(.footnote)
              .foregroundStyle(Theme.inkSoft)
          }
        }
        Spacer(minLength: 0)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(selected ? Theme.accent : Theme.inkFaint.opacity(0.5))
      }
      .padding(Theme.md)
      .background(
        Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .animation(.snappy, value: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Compact capability tile used to explain what can enter ReadSync without
/// turning onboarding into a feature checklist.
struct OnboardingCapabilityCard: View {
  let icon: String
  let title: String
  let detail: String
  var tint: Color = Theme.accent

  var body: some View {
    HStack(alignment: .top, spacing: Theme.md) {
      Image(systemName: icon)
        .font(.title3.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 46, height: 46)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(Theme.ink)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
  }
}

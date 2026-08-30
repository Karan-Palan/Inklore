import SwiftUI

/// Shared building blocks for onboarding. They intentionally make each choice
/// feel like part of a guided reading plan rather than a settings form.

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
    .background {
      LinearGradient(
        colors: [Theme.paper, Theme.mossSoft.opacity(0.16)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      HStack(spacing: Theme.md) {
        if let onBack {
          Button(action: onBack) {
            Image(systemName: "chevron.left")
              .font(.headline.weight(.semibold))
              .foregroundStyle(Theme.ink)
              .frame(width: 44, height: 44)
              .background(Theme.surface, in: Circle())
              .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
          }
          .accessibilityLabel("Go back")
        }
        OnboardingProgressBar(progress: progress)
        if let stepLabel {
          Text(stepLabel)
            .font(.caption2.monospacedDigit().weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.inkFaint)
            .accessibilityHidden(true)
        }
      }

      VStack(alignment: .leading, spacing: Theme.sm) {
        Text(title)
          .font(.system(size: 34, weight: .bold, design: .serif))
          .foregroundStyle(Theme.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.horizontal, Theme.xl)
    .padding(.top, Theme.lg)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Theme.hairline).frame(height: 1)
      OnboardingPrimaryButton(title: ctaTitle, enabled: ctaEnabled, action: onContinue)
        .padding(.horizontal, Theme.xl)
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
    }
    .background(.ultraThinMaterial)
  }
}

/// Progress bar with a visible starting point, so short onboarding still feels
/// like a small, satisfying journey.
struct OnboardingProgressBar: View {
  var progress: Double

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.mossSoft.opacity(0.58))
        Capsule()
          .fill(LinearGradient(colors: [Theme.accent, Theme.sun], startPoint: .leading, endPoint: .trailing))
          .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
          .animation(.snappy, value: progress)
      }
    }
    .frame(height: 7)
    .accessibilityLabel("Onboarding progress, \(Int(progress * 100)) percent")
  }
}

/// Full-width CTA used at the bottom of every step.
struct OnboardingPrimaryButton: View {
  var title: String
  var enabled: Bool = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.sm) {
        Text(title)
        Spacer(minLength: Theme.sm)
        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.bold))
          .accessibilityHidden(true)
      }
      .font(.headline.weight(.bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 58)
      .padding(.horizontal, Theme.lg + 2)
      .background {
        Capsule()
          .fill(enabled ? Theme.accent : Theme.inkFaint)
          .shadow(color: enabled ? Theme.accent.opacity(0.26) : .clear, radius: 12, y: 6)
      }
    }
    .disabled(!enabled)
    .animation(.snappy, value: enabled)
    .accessibilityHint(enabled ? "Continues to the next step" : "Complete this step to continue")
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
            selected ? Theme.accent : Theme.accentSoft.opacity(0.68),
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
        ZStack {
          Circle()
            .fill(selected ? Theme.accent : Theme.surfaceAlt)
            .frame(width: 25, height: 25)
          Image(systemName: selected ? "checkmark" : "circle")
            .font(.caption.weight(.bold))
            .foregroundStyle(selected ? .white : Theme.inkFaint)
        }
      }
      .padding(Theme.md)
      .background(
        selected ? Theme.accentSoft.opacity(0.38) : Theme.surface,
        in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 1.75 : 1)
      )
    }
    .buttonStyle(.plain)
    .animation(.snappy, value: selected)
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Compact capability tile used to explain what can enter Inkflow without
/// turning onboarding into a feature checklist.
struct OnboardingCapabilityCard: View {
  let icon: String
  let title: String
  let detail: String
  var tint: Color = Theme.accent

  var body: some View {
    VStack(spacing: Theme.md) {
      InkflowCapabilityGlyph(sourceIcon: icon, tint: tint)

      VStack(spacing: 4) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Theme.lg)
    .frame(maxWidth: .infinity, alignment: .center)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
    .shadow(color: Theme.shadow.opacity(0.35), radius: 12, y: 5)
  }
}

/// Code-drawn product marks. Universal actions still use familiar system
/// symbols; identity-bearing moments get a coherent Inkflow visual language.
private struct InkflowCapabilityGlyph: View {
  let sourceIcon: String
  let tint: Color

  private var kind: Kind {
    if sourceIcon.contains("link") { return .link }
    if sourceIcon.contains("globe") || sourceIcon.contains("magnifying") { return .discover }
    if sourceIcon.contains("headphone") || sourceIcon.contains("waveform") { return .listen }
    return .pages
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .fill(tint.opacity(0.12))

      switch kind {
      case .pages:
        ZStack {
          RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.25))
            .frame(width: 23, height: 28).offset(x: -5, y: -2).rotationEffect(.degrees(-7))
          RoundedRectangle(cornerRadius: 3).fill(Theme.surface)
            .frame(width: 23, height: 28).offset(x: 4, y: 2)
            .overlay(alignment: .leading) {
              Capsule().fill(tint).frame(width: 3, height: 19).offset(x: 8, y: 2)
            }
          VStack(spacing: 3) {
            Capsule().fill(tint.opacity(0.75)).frame(width: 9, height: 2)
            Capsule().fill(tint.opacity(0.45)).frame(width: 9, height: 2)
          }
          .offset(x: 6, y: 2)
        }
      case .discover:
        ZStack {
          Circle().stroke(tint, lineWidth: 2.2).frame(width: 24, height: 24)
          Capsule().fill(tint).frame(width: 2, height: 20)
          Capsule().stroke(tint, lineWidth: 1.6).frame(width: 12, height: 24)
          Capsule().fill(tint).frame(width: 10, height: 2)
            .offset(x: 12, y: 13).rotationEffect(.degrees(45))
        }
      case .link:
        ZStack {
          RoundedRectangle(cornerRadius: 7).stroke(tint, lineWidth: 2.4)
            .frame(width: 23, height: 12).offset(x: -7).rotationEffect(.degrees(-38))
          RoundedRectangle(cornerRadius: 7).stroke(tint, lineWidth: 2.4)
            .frame(width: 23, height: 12).offset(x: 7).rotationEffect(.degrees(-38))
          Capsule().fill(Theme.surface).frame(width: 10, height: 5).rotationEffect(.degrees(-38))
        }
      case .listen:
        HStack(alignment: .center, spacing: 2.5) {
          ForEach([10.0, 18.0, 26.0, 18.0, 10.0], id: \.self) { height in
            Capsule().fill(tint).frame(width: 3, height: height)
          }
        }
      }
    }
    .frame(width: 50, height: 50)
    .accessibilityHidden(true)
  }

  private enum Kind { case pages, discover, link, listen }
}

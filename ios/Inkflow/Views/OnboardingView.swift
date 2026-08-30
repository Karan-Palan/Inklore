import SwiftUI

/// A short, product-led first run. It explains the core Inkflow loop, captures
/// only choices we can use immediately, then opens the real app without auth or
/// a paywall.
struct OnboardingView: View {
  /// Called when onboarding finishes and the app should reveal the main tabs.
  var onFinish: () -> Void

  @State private var state = OnboardingState()
  @State private var step: Step = .welcome

  enum Step: Int, CaseIterable {
    case welcome, sources, preferences, genre, setup
  }

  private var progress: Double {
    let total = Double(Step.allCases.count - 1)
    return Double(step.rawValue) / total
  }

  private var stepLabel: String {
    "STEP \(step.rawValue) / \(Step.allCases.count - 2)"
  }

  var body: some View {
    ZStack {
      switch step {
      case .welcome:
        WelcomeStep { advance() }
      case .sources:
        SourcesStep(progress: progress, stepLabel: stepLabel, onBack: back, onNext: advance)
      case .preferences:
        PreferencesStep(
          state: state, progress: progress, stepLabel: stepLabel,
          onBack: back, onNext: advance)
      case .genre:
        GenreStep(
          state: state, progress: progress, stepLabel: stepLabel,
          onBack: back, onNext: advance)
      case .setup:
        OnboardingSetupView(state: state, onFinish: finish)
      }
    }
    .transition(
      .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
      )
    )
    .animation(.smooth(duration: 0.35), value: step)
    .__tenxTrackView("OnboardingView")
  }

  private func advance() {
    guard let next = Step(rawValue: step.rawValue + 1) else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    step = next
  }

  private func back() {
    guard let prev = Step(rawValue: step.rawValue - 1) else { return }
    step = prev
  }

  private func finish() {
    onFinish()
  }
}

// MARK: - Welcome

private struct WelcomeStep: View {
  var onStart: () -> Void
  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.paper, Theme.mossSoft.opacity(0.58), Theme.accentSoft.opacity(0.42)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      Circle()
        .fill(Theme.sun.opacity(0.28))
        .frame(width: 260, height: 260)
        .blur(radius: 6)
        .offset(x: 125, y: -310)
        .accessibilityHidden(true)

      VStack(spacing: Theme.xl) {
        Spacer(minLength: Theme.lg)

        HStack(spacing: 7) {
          Image(systemName: "sparkle")
          Text("INKFLOW")
            .tracking(3.2)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(Theme.moss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inkflow")

        SyncReaderPreview(isVisible: appeared)
          .padding(.horizontal, Theme.xl)

        VStack(spacing: Theme.md) {
          Text("Make room\nfor a better story.")
            .font(.system(size: 37, weight: .bold, design: .serif))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
          Text("Read, listen, and keep the ideas worth returning to — all from one thoughtfully quiet shelf.")
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.xl)
        }
        Spacer()
        OnboardingPrimaryButton(title: "Build my reading ritual") { onStart() }
          .padding(.horizontal, Theme.xl)
        Text("No account needed · your library stays yours")
          .font(.footnote)
          .foregroundStyle(Theme.inkFaint)
          .padding(.bottom, Theme.lg)
      }
    }
    .onAppear { appeared = true }
    .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: appeared)
  }
}

private struct SyncReaderPreview: View {
  let isVisible: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("A little reading ritual", systemImage: "book.closed.fill")
          .font(.caption.weight(.semibold))
        Spacer()
        Image(systemName: "bookmark.fill")
      }
      .foregroundStyle(Theme.inkSoft)
      .padding(Theme.md)

      VStack(alignment: .leading, spacing: 10) {
        Text("TODAY'S QUIET CHAPTER")
          .font(.caption2.weight(.bold))
          .tracking(1.2)
          .foregroundStyle(Theme.inkFaint)
        Text("A book is a place to meet your thoughts, one unhurried page at a time.")
          .font(.system(.title3, design: .serif))
          .foregroundStyle(Theme.ink)
          .lineSpacing(5)
          .overlay(alignment: .bottomLeading) {
            Capsule()
              .fill(Theme.highlightYellow.opacity(0.55))
              .frame(width: 218, height: 9)
              .offset(y: 2)
              .zIndex(-1)
          }
      }
      .padding(.horizontal, Theme.lg)
      .padding(.bottom, Theme.lg)

      HStack(spacing: Theme.md) {
        Image(systemName: "gobackward.15")
        Image(systemName: "pause.fill")
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Theme.accent, in: Circle())
        Image(systemName: "goforward.15")
        AudioWaveform(level: 0.55, isPlaying: true, tint: Theme.accent)
          .frame(height: 28)
          .clipped()
        Text("1.2×")
          .font(.caption.weight(.bold))
      }
      .foregroundStyle(Theme.ink)
      .padding(Theme.md)
      .background(Theme.surfaceAlt.opacity(0.8))
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
    .shadow(color: Theme.ink.opacity(0.12), radius: 24, y: 14)
    .scaleEffect(isVisible ? 1 : 0.94)
    .opacity(isVisible ? 1 : 0)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("A book page playing in synchronized audiobook mode")
  }
}

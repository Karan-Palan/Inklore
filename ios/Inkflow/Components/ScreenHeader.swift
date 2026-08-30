import SwiftUI

/// A compact, top-pinned screen header used across the main tabs so every screen
/// sits flush under the status bar (no large-title gap). Shows a bold title with
/// optional trailing controls, and an optional inline search field below.
struct ScreenHeader<Trailing: View>: View {
  let title: String
  var trailing: Trailing

  init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .center) {
      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(Theme.ink)
      Spacer(minLength: Theme.sm)
      trailing
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.lg)
    .padding(.bottom, Theme.xs)
    .background(Theme.paper)
  }
}

extension ScreenHeader where Trailing == EmptyView {
  init(_ title: String) {
    self.title = title
    self.trailing = EmptyView()
  }
}

/// A reusable inline search field matching the app's pill style, for screens that
/// previously used `.searchable`.
struct InlineSearchField: View {
  let prompt: String
  @Binding var text: String
  var focused: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: Theme.sm) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Theme.inkFaint)
      TextField(prompt, text: $text)
        .focused(focused)
        .submitLabel(.search)
        .autocorrectionDisabled()
      if !text.isEmpty {
        Button {
          text = ""
          focused.wrappedValue = true
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Theme.inkFaint)
        }
      }
    }
    .padding(.horizontal, Theme.md)
    .padding(.vertical, 11)
    .background(Theme.surfaceAlt, in: Capsule())
    .padding(.horizontal, Theme.lg)
    .padding(.bottom, Theme.sm)
    .background(Theme.paper)
  }
}

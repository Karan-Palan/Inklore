import SwiftUI

/// Horizontally scrolling pill category filter — mirrors the Kindle home/browse
/// category chips.
struct CategoryFilterBar: View {
  let categories: [String]
  @Binding var selection: String

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Theme.sm) {
        ForEach(categories, id: \.self) { category in
          let isSelected = category == selection
          Button {
            withAnimation(.snappy) { selection = category }
          } label: {
            HStack(spacing: 6) {
              if isSelected {
                Image(systemName: "checkmark")
                  .font(.caption2.weight(.bold))
              }
              Text(category)
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : Theme.inkSoft)
            .padding(.horizontal, Theme.lg)
            .padding(.vertical, Theme.sm + 2)
            .background(
              Capsule(style: .continuous)
                .fill(isSelected ? Theme.accent : Theme.surfaceAlt)
            )
            .overlay {
              Capsule(style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.hairline.opacity(0.8))
            }
          }
          .buttonStyle(.plain)
          .contentShape(Capsule())
          .accessibilityLabel("\(category)\(isSelected ? ", selected" : "")")
          .sensoryFeedback(.selection, trigger: selection)
        }
      }
      .padding(.horizontal, Theme.lg)
    }
  }
}

/// Section header with an optional "See more" trailing action.
struct SectionHeader: View {
  let title: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.title3.weight(.bold))
        .foregroundStyle(Theme.ink)
      Spacer()
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.accent)
      }
    }
    .padding(.horizontal, Theme.lg)
  }
}

/// Thin progress bar used under continue-reading covers.
struct ThinProgressBar: View {
  let progress: Double
  var tint: Color = Theme.accent

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.hairline)
        Capsule()
          .fill(tint)
          .frame(width: max(progress > 0 ? 3 : 0, geo.size.width * min(max(progress, 0), 1)))
      }
    }
    .frame(height: 4)
  }
}

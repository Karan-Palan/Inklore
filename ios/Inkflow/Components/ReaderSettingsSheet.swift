import SwiftUI

/// The "Aa" reader settings sheet — Font / Layout / Themes tabs with a font
/// picker, text-size + brightness sliders, line-spacing/margin controls, and
/// light / sepia / night page themes.
struct ReaderSettingsSheet: View {
  @Bindable var settings: ReaderSettings
  @Environment(\.dismiss) private var dismiss

  @State private var tab: SettingsTab = .font

  enum SettingsTab: String, CaseIterable, Identifiable {
    case font = "Font"
    case layout = "Layout"
    case themes = "Themes"
    var id: String { rawValue }
  }

  var body: some View {
    VStack(spacing: Theme.lg) {
      header
      tabPicker

      Group {
        switch tab {
        case .font: fontTab
        case .layout: layoutTab
        case .themes: themesTab
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 0)
    }
    .padding(Theme.xl)
    .presentationBackground(Theme.surface)
  }

  // MARK: Header

  private var header: some View {
    HStack {
      Text("Aa")
        .font(.system(size: 28, weight: .bold, design: .serif))
        .foregroundStyle(Theme.accent)
        .frame(width: 42, height: 42)
        .background(Theme.accentSoft.opacity(0.55), in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text("Reading preferences")
          .font(.headline.weight(.bold))
          .foregroundStyle(Theme.ink)
        Text("Tune the page to your eyes")
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
      }
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .foregroundStyle(Theme.inkFaint)
      }
      .accessibilityLabel("Close reading preferences")
    }
  }

  private var tabPicker: some View {
    Picker("Section", selection: $tab) {
      ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)
  }

  // MARK: Font tab

  private var fontTab: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Theme.md) {
          ForEach(ReaderFont.allCases) { family in
            Button {
              settings.font = family
            } label: {
              VStack(spacing: Theme.xs) {
                Text("Ag")
                  .font(family.font(size: 26))
                Text(family.rawValue)
                  .font(.caption)
              }
              .foregroundStyle(settings.font == family ? Theme.accent : Theme.inkSoft)
              .frame(width: 84, height: 72)
              .background(
                settings.font == family ? Theme.accentSoft : Theme.surfaceAlt,
                in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
              )
              .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                  .strokeBorder(
                    settings.font == family ? Theme.accent : .clear, lineWidth: 1.5)
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(family.rawValue) font")
            .accessibilityAddTraits(settings.font == family ? .isSelected : [])
          }
        }
        .padding(.vertical, 2)
      }

      sliderRow(
        title: "Text size",
        minIcon: "textformat.size.smaller",
        maxIcon: "textformat.size.larger",
        value: $settings.fontSize, range: 14...26, step: 1)
    }
  }

  // MARK: Layout tab

  private var layoutTab: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      sliderRow(
        title: "Line spacing",
        minIcon: "text.alignleft",
        maxIcon: "text.justify",
        value: $settings.lineSpacing, range: 2...16, step: 1)

      sliderRow(
        title: "Margins",
        minIcon: "arrow.right.and.line.vertical.and.arrow.left",
        maxIcon: "arrow.left.and.line.vertical.and.arrow.right",
        value: $settings.margins, range: 12...48, step: 2)

      sliderRow(
        title: "Brightness",
        minIcon: "sun.min",
        maxIcon: "sun.max.fill",
        value: $settings.brightness, range: 0.4...1.0, step: 0.05)
    }
  }

  // MARK: Themes tab

  private var themesTab: some View {
    HStack(spacing: Theme.lg) {
      ForEach(ReaderTheme.allCases) { theme in
        Button {
          settings.theme = theme
        } label: {
          VStack(spacing: Theme.sm) {
            ZStack {
              RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .fill(theme.pageBackground)
              Text("Ag")
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(theme.textColor)
            }
            .frame(height: 76)
            .overlay(
              RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .strokeBorder(
                  settings.theme == theme ? Theme.accent : Theme.hairline,
                  lineWidth: settings.theme == theme ? 2.5 : 1)
            )
            Text(theme.rawValue)
              .font(.caption.weight(settings.theme == theme ? .bold : .regular))
              .foregroundStyle(settings.theme == theme ? Theme.accent : Theme.inkSoft)
          }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(theme.rawValue) theme")
        .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
      }
    }
  }

  // MARK: Helpers

  private func sliderRow(
    title: String, minIcon: String, maxIcon: String,
    value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.ink)
      HStack(spacing: Theme.md) {
        Image(systemName: minIcon).foregroundStyle(Theme.inkFaint)
        Slider(value: value, in: range, step: step)
          .tint(Theme.accent)
          .accessibilityLabel(title)
          .accessibilityValue("\(Int(value.wrappedValue))")
        Image(systemName: maxIcon).foregroundStyle(Theme.inkFaint)
      }
    }
  }

  private func sliderRow(
    title: String, minIcon: String, maxIcon: String,
    value: Binding<Double>, range: ClosedRange<Double>, step: Double
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.ink)
      HStack(spacing: Theme.md) {
        Image(systemName: minIcon).foregroundStyle(Theme.inkFaint)
        Slider(value: value, in: range, step: step)
          .tint(Theme.accent)
          .accessibilityLabel(title)
          .accessibilityValue("\(Int(value.wrappedValue * 100)) percent")
        Image(systemName: maxIcon).foregroundStyle(Theme.inkFaint)
      }
    }
  }
}

#Preview {
  Color.gray
    .sheet(isPresented: .constant(true)) {
      ReaderSettingsSheet(settings: ReaderSettings())
        .presentationDetents([.height(420)])
    }
}

import SwiftUI
import UIKit

/// Central design tokens for Inkflow. The palette is deliberately quiet enough
/// for long reading sessions, with a warm signal colour for moments that need
/// momentum (starting a book, making a choice, or resuming a session).
enum Theme {
  // MARK: Inkflow palette
  static let ink = Color(light: 0x16342E, dark: 0xE6F0EB)  // primary text / strong elements
  static let inkSoft = Color(light: 0x5C716B, dark: 0xA8BBB4)  // secondary text
  static let inkFaint = Color(light: 0x8C9A95, dark: 0x82968F)  // tertiary / captions
  static let paper = Color(light: 0xF7F8F4, dark: 0x0D1513)  // app background
  static let surface = Color(light: 0xFFFFFF, dark: 0x17211E)  // cards / sheets
  static let surfaceAlt = Color(light: 0xEAF0EB, dark: 0x202E2A)  // pills, wells
  static let accent = Color(light: 0xD96745, dark: 0xE97B58)  // warm, optimistic action colour
  static let accentDeep = Color(light: 0xAD472E, dark: 0xF09A7D)
  static let accentSoft = Color(light: 0xF6D9CD, dark: 0x4A2A22)
  static let moss = Color(light: 0x2F6B5F, dark: 0x79B9A9)
  static let mossSoft = Color(light: 0xCFE4D9, dark: 0x24433B)
  static let sun = Color(light: 0xF3C95E, dark: 0xDDB54F)
  static let lilac = Color(light: 0xD8C6E9, dark: 0x473B57)
  static let hairline = Color(light: 0xDDE6DF, dark: 0x2D3B36)
  static let shadow = Color(
    light: 0x17372F, dark: 0x000000, alpha: 0.12, darkAlpha: 0.38)

  // Highlight swatch colors (used in reader selection + notebook)
  static let highlightYellow = Color(light: 0xF4D67A, dark: 0xD6B84F)
  static let highlightGreen = Color(light: 0xAFD6A6, dark: 0x78AD72)
  static let highlightBlue = Color(light: 0x9FC4E8, dark: 0x74A6D1)
  static let highlightPink = Color(light: 0xEBA7BE, dark: 0xCA7F9B)

  // MARK: Spacing scale
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
  static let xxxl: CGFloat = 40

  // MARK: Radius
  static let radiusSm: CGFloat = 8
  static let radiusMd: CGFloat = 14
  static let radiusLg: CGFloat = 22
  static let radiusXl: CGFloat = 30
}

extension Color {
  /// A brand color that automatically follows the current UIKit appearance.
  /// UIKit-backed colors also adapt inside sheets, tab bars, and representables.
  init(light: UInt, dark: UInt, alpha: Double = 1, darkAlpha: Double? = nil) {
    self.init(uiColor: UIColor { traits in
      let isDark = traits.userInterfaceStyle == .dark
      let hex = isDark ? dark : light
      return UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: CGFloat(isDark ? (darkAlpha ?? alpha) : alpha)
      )
    })
  }

  /// Preserves a content accent in light mode and lifts its luminance in dark
  /// mode. This is useful for data-driven genre colors that do not have a
  /// hand-authored dark variant in the model.
  init(adaptiveAccentHex hex: UInt) {
    self.init(uiColor: UIColor { traits in
      let base = UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
      guard traits.userInterfaceStyle == .dark else { return base }

      var hue: CGFloat = 0
      var saturation: CGFloat = 0
      var brightness: CGFloat = 0
      var alpha: CGFloat = 0
      guard base.getHue(
        &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
      else { return base }
      return UIColor(
        hue: hue,
        saturation: min(saturation, 0.72),
        brightness: max(brightness, 0.76),
        alpha: alpha
      )
    })
  }

  init(hex: UInt, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }
}

/// Reader page themes (light / sepia / dark) used by the Aa settings sheet.
enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
  case light = "Paper"
  case sepia = "Sepia"
  case dark = "Night"

  var id: String { rawValue }

  var pageBackground: Color {
    switch self {
    case .light: return Color(hex: 0xFCFAF4)
    case .sepia: return Color(hex: 0xF3E7CF)
    case .dark: return Color(hex: 0x16161A)
    }
  }

  var textColor: Color {
    switch self {
    case .light: return Color(hex: 0x1C1B19)
    case .sepia: return Color(hex: 0x453B2A)
    case .dark: return Color(hex: 0xD8D4CC)
    }
  }

  var chromeTint: Color {
    switch self {
    case .dark: return .white
    default: return Theme.ink
    }
  }

  var icon: String {
    switch self {
    case .light: return "sun.max"
    case .sepia: return "book.closed"
    case .dark: return "moon.stars"
    }
  }
}

/// Reader font families offered in the Aa sheet.
enum ReaderFont: String, CaseIterable, Identifiable, Codable {
  case serif = "Literata"
  case newYork = "New York"
  case rounded = "Rounded"
  case mono = "Mono"

  var id: String { rawValue }

  func font(size: CGFloat) -> Font {
    switch self {
    case .serif: return .system(size: size, design: .serif)
    case .newYork: return .custom("New York", size: size)
    case .rounded: return .system(size: size, design: .rounded)
    case .mono: return .system(size: size, design: .monospaced)
    }
  }

  /// UIFont equivalent used by the TextKit paginator + reader page rendering.
  func uiFont(size: CGFloat) -> UIFont {
    let base = UIFont.systemFont(ofSize: size)
    switch self {
    case .serif:
      if let descriptor = base.fontDescriptor.withDesign(.serif) {
        return UIFont(descriptor: descriptor, size: size)
      }
      return UIFont(name: "Georgia", size: size) ?? base
    case .newYork:
      if let descriptor = base.fontDescriptor.withDesign(.serif) {
        return UIFont(descriptor: descriptor, size: size)
      }
      return base
    case .rounded:
      if let descriptor = base.fontDescriptor.withDesign(.rounded) {
        return UIFont(descriptor: descriptor, size: size)
      }
      return base
    case .mono:
      return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
  }
}

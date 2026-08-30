import SwiftUI
import UIKit

/// Central design tokens for Inkflow. The palette is deliberately quiet enough
/// for long reading sessions, with a warm signal colour for moments that need
/// momentum (starting a book, making a choice, or resuming a session).
enum Theme {
  // MARK: Inkflow palette
  static let ink = Color(hex: 0x16342E)  // primary text / strong elements
  static let inkSoft = Color(hex: 0x5C716B)  // secondary text
  static let inkFaint = Color(hex: 0x8C9A95)  // tertiary / captions
  static let paper = Color(hex: 0xF7F8F4)  // app background
  static let surface = Color(hex: 0xFFFFFF)  // cards / sheets
  static let surfaceAlt = Color(hex: 0xEAF0EB)  // pills, wells
  static let accent = Color(hex: 0xD96745)  // warm, optimistic action colour
  static let accentDeep = Color(hex: 0xAD472E)
  static let accentSoft = Color(hex: 0xF6D9CD)
  static let moss = Color(hex: 0x2F6B5F)
  static let mossSoft = Color(hex: 0xCFE4D9)
  static let sun = Color(hex: 0xF3C95E)
  static let lilac = Color(hex: 0xD8C6E9)
  static let hairline = Color(hex: 0xDDE6DF)
  static let shadow = Color(hex: 0x17372F, alpha: 0.12)

  // Highlight swatch colors (used in reader selection + notebook)
  static let highlightYellow = Color(hex: 0xF4D67A)
  static let highlightGreen = Color(hex: 0xAFD6A6)
  static let highlightBlue = Color(hex: 0x9FC4E8)
  static let highlightPink = Color(hex: 0xEBA7BE)

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

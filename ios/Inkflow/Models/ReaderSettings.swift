import SwiftUI

/// Shared, observable reader preferences driven by the Aa settings sheet.
@Observable
final class ReaderSettings {
  var font: ReaderFont = .serif
  var fontSize: CGFloat = 19
  var lineSpacing: CGFloat = 8
  var theme: ReaderTheme = .light
  var brightness: Double = 1.0
  var margins: CGFloat = 24
}

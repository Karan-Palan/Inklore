import SwiftUI
import UIKit

/// A single, non-scrolling reader page rendered with UITextView so the user gets
/// native text selection (for highlights/notes) and a justified, paginated look.
struct ReaderPageView: UIViewRepresentable {
  let attributed: NSAttributedString
  let pageRange: NSRange
  let highlights: [(range: NSRange, color: UIColor)]
  let activeWordRange: NSRange?
  let onSelect: (_ text: String, _ range: NSRange) -> Void
  /// Fired when the reader taps inside an existing highlight (global char index).
  var onTapHighlight: ((_ globalIndex: Int) -> Void)? = nil

  func makeUIView(context: Context) -> UITextView {
    let tv = UITextView()
    tv.isScrollEnabled = false
    tv.isEditable = false
    tv.isSelectable = true
    tv.backgroundColor = .clear
    tv.textContainerInset = .zero
    tv.textContainer.lineFragmentPadding = 0
    tv.delegate = context.coordinator
    tv.dataDetectorTypes = []

    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tap.cancelsTouchesInView = false
    tv.addGestureRecognizer(tap)
    context.coordinator.textView = tv
    // Without these, a non-scrolling UITextView reports an unbounded intrinsic
    // width and SwiftUI centers it, so text bleeds off both page edges. Make the
    // container track the assigned width and let the SwiftUI frame win.
    tv.textContainer.widthTracksTextView = true
    tv.textContainer.heightTracksTextView = true
    tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
    tv.setContentHuggingPriority(.defaultLow, for: .vertical)
    return tv
  }

  func updateUIView(_ tv: UITextView, context: Context) {
    context.coordinator.parent = self

    guard pageRange.location + pageRange.length <= attributed.length else {
      tv.attributedText = NSAttributedString(string: "")
      return
    }

    let pageString = NSMutableAttributedString(
      attributedString: attributed.attributedSubstring(from: pageRange))

    // Apply highlight backgrounds, translating global ranges into page-local ranges.
    for hl in highlights {
      if let local = intersectLocal(hl.range, in: pageRange) {
        pageString.addAttribute(
          .backgroundColor, value: hl.color.withAlphaComponent(0.55), range: local)
      }
    }

    // Karaoke-style active narration word.
    if let word = activeWordRange, let local = intersectLocal(word, in: pageRange) {
      pageString.addAttribute(
        .backgroundColor, value: UIColor(Theme.accent).withAlphaComponent(0.35), range: local)
    }

    tv.attributedText = pageString
  }

  /// Convert a global range into a range local to the page, clipped to the page.
  private func intersectLocal(_ range: NSRange, in page: NSRange) -> NSRange? {
    let start = max(range.location, page.location)
    let end = min(range.location + range.length, page.location + page.length)
    guard end > start else { return nil }
    return NSRange(location: start - page.location, length: end - start)
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: ReaderPageView
    weak var textView: UITextView?
    init(_ parent: ReaderPageView) { self.parent = parent }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let tv = textView, tv.selectedRange.length == 0,
        let onTapHighlight = parent.onTapHighlight
      else { return }
      let point = gesture.location(in: tv)
      let layout = tv.layoutManager
      let container = tv.textContainer
      guard layout.numberOfGlyphs > 0 else { return }
      var fraction: CGFloat = 0
      let glyphIndex = layout.glyphIndex(
        for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
      let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
      let global = parent.pageRange.location + charIndex
      let hit = parent.highlights.contains { NSLocationInRange(global, $0.range) }
      if hit { onTapHighlight(global) }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      let sel = textView.selectedRange
      guard sel.length > 2,
        let textRange = textView.selectedTextRange,
        let selected = textView.text(in: textRange)
      else { return }
      // Translate page-local selection back to a global range.
      let global = NSRange(
        location: parent.pageRange.location + sel.location, length: sel.length)
      parent.onSelect(selected, global)
    }
  }
}

import SwiftUI
import UIKit

/// A single, non-scrolling reader page rendered with UITextView so the user gets
/// native text selection (for highlights/notes) and a justified, paginated look.
struct ReaderPageView: UIViewRepresentable {
  enum TapZone { case left, center, right }

  /// ReaderView supplies only highlights intersecting this page. Keeping this
  /// payload local avoids rebuilding/scanning a book's complete highlight list
  /// for each narration-word update.
  struct Highlight {
    let id: UUID
    let range: NSRange
    let color: UIColor
  }

  let attributed: NSAttributedString
  let pageRange: NSRange
  let highlights: [Highlight]
  let activeWordRange: NSRange?
  let onSelect: (_ text: String, _ range: NSRange) -> Void
  /// A concise VoiceOver announcement supplied by the paginated reader.
  var accessibilityPageDescription: String? = nil
  /// Fired when the reader taps inside an existing page-local highlight.
  var onTapHighlight: ((_ highlightID: UUID) -> Void)? = nil
  /// Page navigation is handled by the text view's non-cancelling tap
  /// recognizer so an invisible SwiftUI overlay never steals long presses from
  /// native text selection.
  var onTapZone: ((TapZone) -> Void)? = nil

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
    tv.accessibilityHint = "Double tap and hold text to select a passage. Tap the center of the page to show reader controls."

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
    tv.accessibilityLabel = accessibilityPageDescription ?? "Book page"

    guard pageRange.location + pageRange.length <= attributed.length else {
      tv.attributedText = NSAttributedString(string: "")
      context.coordinator.resetRenderedPage()
      return
    }

    context.coordinator.renderStaticPageIfNeeded(in: tv)
    context.coordinator.updateActiveWord(in: tv)
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
    private var renderedAttributed: NSAttributedString?
    private var renderedPageRange: NSRange?
    private var renderedHighlights: [Highlight] = []
    private var activeLocalRange: NSRange?
    init(_ parent: ReaderPageView) { self.parent = parent }

    func resetRenderedPage() {
      renderedAttributed = nil
      renderedPageRange = nil
      renderedHighlights = []
      activeLocalRange = nil
    }

    /// Rebuild the static text only when its page/highlights changed. Active
    /// narration then mutates just the old and new word ranges in textStorage.
    func renderStaticPageIfNeeded(in textView: UITextView) {
      guard needsStaticRender else { return }
      let pageString = NSMutableAttributedString(
        attributedString: parent.attributed.attributedSubstring(from: parent.pageRange))
      for highlight in parent.highlights {
        if let local = parent.intersectLocal(highlight.range, in: parent.pageRange) {
          pageString.addAttribute(
            .backgroundColor, value: highlight.color.withAlphaComponent(0.55), range: local)
        }
      }
      let rendered = NSAttributedString(attributedString: pageString)
      textView.attributedText = rendered
      renderedAttributed = rendered
      renderedPageRange = parent.pageRange
      renderedHighlights = parent.highlights
      activeLocalRange = nil
    }

    func updateActiveWord(in textView: UITextView) {
      let next = parent.activeWordRange.flatMap {
        parent.intersectLocal($0, in: parent.pageRange)
      }
      guard !NSEqualRanges(next ?? NSRange(location: NSNotFound, length: 0),
                           activeLocalRange ?? NSRange(location: NSNotFound, length: 0))
      else { return }

      textView.textStorage.beginEditing()
      if let activeLocalRange, let renderedAttributed {
        restoreBaseAttributes(renderedAttributed, to: activeLocalRange, in: textView.textStorage)
      }
      if let next {
        textView.textStorage.addAttribute(
          .backgroundColor, value: UIColor(Theme.accent).withAlphaComponent(0.35), range: next)
      }
      textView.textStorage.endEditing()
      activeLocalRange = next
    }

    private var needsStaticRender: Bool {
      guard renderedPageRange == parent.pageRange,
        renderedAttributed != nil,
        renderedHighlights.count == parent.highlights.count
      else { return true }
      return zip(renderedHighlights, parent.highlights).contains {
        $0.id != $1.id || !NSEqualRanges($0.range, $1.range) || !$0.color.isEqual($1.color)
      }
    }

    private func restoreBaseAttributes(
      _ base: NSAttributedString, to range: NSRange, in storage: NSTextStorage
    ) {
      base.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
        storage.setAttributes(attributes, range: subrange)
      }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let tv = textView, tv.selectedRange.length == 0 else { return }
      let point = gesture.location(in: tv)
      let layout = tv.layoutManager
      let container = tv.textContainer
      guard layout.numberOfGlyphs > 0 else { return }
      var fraction: CGFloat = 0
      let glyphIndex = layout.glyphIndex(
        for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
      let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
      let global = parent.pageRange.location + charIndex
      if let hit = parent.highlights.first(where: { NSLocationInRange(global, $0.range) }),
        let onTapHighlight = parent.onTapHighlight
      {
        onTapHighlight(hit.id)
        return
      }

      guard let onTapZone = parent.onTapZone else { return }
      let zoneFraction = point.x / max(tv.bounds.width, 1)
      if zoneFraction < 0.3 {
        onTapZone(.left)
      } else if zoneFraction > 0.7 {
        onTapZone(.right)
      } else {
        onTapZone(.center)
      }
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

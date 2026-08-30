import SwiftUI
import WebKit

/// A `UIViewRepresentable` wrapping `WKWebView` to render one EPUB chapter file
/// with full original formatting + images, plus an injected reader-theme
/// stylesheet. Reports scroll position and forwards tap-zone gestures so the
/// SwiftUI reader can flip chapters and toggle chrome.
struct EpubWebView: UIViewRepresentable {
  enum TapZone { case left, right, center }

  let chapterURL: URL
  let baseURL: URL
  let settings: ReaderSettings
  let initialScroll: Double
  let onScroll: (Double) -> Void
  let onTapZone: (TapZone) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.scrollView.delegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.contentInsetAdjustmentBehavior = .never

    // Tap zones: left third = back, right third = forward, center = chrome.
    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tap.delegate = context.coordinator
    webView.addGestureRecognizer(tap)

    context.coordinator.webView = webView
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    // Reload chapter if it changed.
    if context.coordinator.loadedURL != chapterURL {
      context.coordinator.loadedURL = chapterURL
      context.coordinator.pendingScroll = initialScroll
      let access = baseURL
      webView.loadFileURL(chapterURL, allowingReadAccessTo: access)
    } else {
      // Same chapter, settings may have changed → re-inject CSS.
      context.coordinator.injectStyle()
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate,
    UIGestureRecognizerDelegate
  {
    let parent: EpubWebView
    weak var webView: WKWebView?
    var loadedURL: URL?
    var pendingScroll: Double = 0

    init(_ parent: EpubWebView) { self.parent = parent }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      injectStyle()
      // Restore scroll after layout settles.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
        guard let self, self.pendingScroll > 0 else { return }
        let target = self.pendingScroll
        webView.evaluateJavaScript(
          "window.scrollTo(0, document.body.scrollHeight * \(target));")
        self.pendingScroll = 0
      }
    }

    func injectStyle() {
      guard let webView else { return }
      let theme = parent.settings.theme
      let bg = theme.pageBackground.hexString
      let fg = theme.textColor.hexString
      let size = Int(parent.settings.fontSize)
      let margin = Int(parent.settings.margins)
      let lineHeight = 1.4 + Double(parent.settings.lineSpacing) / 20.0
      let family = parent.settings.font.cssFamily

      let css = """
        var s = document.getElementById('readsync-style') || document.createElement('style');
        s.id = 'readsync-style';
        s.innerHTML = `
          html { -webkit-text-size-adjust: none; }
          html, body { background: \(bg) !important; color: \(fg) !important;
            font-family: \(family) !important; font-size: \(size)px !important;
            line-height: \(lineHeight) !important;
            padding: 56px \(margin)px 96px \(margin)px !important; margin: 0 !important;
            -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
            word-wrap: break-word; overflow-wrap: break-word; hyphens: auto; }
          p { color: \(fg) !important; margin: 0 0 0.85em 0 !important;
            text-align: justify; orphans: 2; widows: 2; }
          div, span, li, td, blockquote, section { color: \(fg) !important; }
          a { color: \(fg) !important; text-decoration: none; }
          img, svg, image, figure { max-width: 100% !important; height: auto !important;
            display: block; margin: 1em auto !important; border-radius: 4px; }
          h1,h2,h3,h4,h5,h6 { color: \(fg) !important; line-height: 1.25 !important;
            margin: 1.2em 0 0.5em 0 !important; font-weight: 700; }
          blockquote { border-left: 3px solid \(fg)33; margin: 1em 0; padding-left: 1em;
            font-style: italic; }
          hr { border: none; border-top: 1px solid \(fg)22; margin: 1.5em 0; }
          table { max-width: 100% !important; }
        `;
        if (!s.parentNode) { document.head.appendChild(s); }
        """
      webView.evaluateJavaScript(css)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      let height = scrollView.contentSize.height - scrollView.bounds.height
      guard height > 0 else { return }
      let fraction = min(1, max(0, scrollView.contentOffset.y / height))
      parent.onScroll(Double(fraction))
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let view = gesture.view else { return }
      let x = gesture.location(in: view).x
      let width = view.bounds.width
      if x < width * 0.3 {
        parent.onTapZone(.left)
      } else if x > width * 0.7 {
        parent.onTapZone(.right)
      } else {
        parent.onTapZone(.center)
      }
    }

    func gestureRecognizer(
      _ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
  }
}

extension ReaderFont {
  /// CSS font-family stack matching the reader's chosen family.
  var cssFamily: String {
    switch self {
    case .serif: return "Georgia, 'Times New Roman', serif"
    case .newYork: return "'New York', Georgia, serif"
    case .rounded: return "-apple-system, 'SF Pro Rounded', system-ui, sans-serif"
    case .mono: return "ui-monospace, Menlo, monospace"
    }
  }
}

extension Color {
  /// Hex string (#rrggbb) for injecting into CSS.
  var hexString: String {
    let ui = UIColor(self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
  }
}

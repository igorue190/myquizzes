//
//  MathView.swift
//  DesignSystem
//
//  Renders LaTeX with KaTeX inside a WKWebView, fully offline (the KaTeX CSS/JS
//  and woff2 fonts are bundled as package resources). Used by RichText for any
//  paragraph/block that contains math. The web view is transparent, non-scrolling,
//  and self-sizes to its content height so it lays out like normal SwiftUI text.
//

import SwiftUI
import WebKit

/// Location of the bundled KaTeX assets (CSS/JS/fonts), used as the web view's
/// base URL so relative `fonts/…` references in the CSS resolve on-device.
enum KaTeXAssets {
    static let baseURL: URL? = Bundle.module.resourceURL?.appendingPathComponent("KaTeX")

    /// Build a full HTML document that typesets the given body (which contains
    /// `[data-tex]` spans) with KaTeX, in the requested text color.
    static func document(body: String, colorHex: String) -> String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <link rel="stylesheet" href="katex.min.css">
        <style>
          html,body { margin:0; padding:0; background:transparent; }
          body { color:\(colorHex); font: -apple-system, system-ui; font-size:17px;
                 line-height:1.4; -webkit-text-size-adjust:100%; word-wrap:break-word; }
          a { color:\(colorHex); }
          code { font-family: ui-monospace, Menlo, monospace; font-size:0.95em; }
          .kx-display { text-align:center; margin:0.2em 0; overflow-x:auto; }
        </style>
        <script src="katex.min.js"></script>
        </head><body>
        \(body)
        <script>
          document.querySelectorAll('[data-tex]').forEach(function(el){
            try {
              katex.render(el.getAttribute('data-tex'), el, {
                displayMode: el.getAttribute('data-display') === '1',
                throwOnError: false
              });
            } catch (e) { el.textContent = el.getAttribute('data-tex'); }
          });
        </script>
        </body></html>
        """
    }
}

/// A self-sizing SwiftUI wrapper around the KaTeX web view.
struct MathView: View {
    let html: String
    @State private var height: CGFloat = 22

    var body: some View {
        MathWebView(html: html, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MathWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the content actually changes, so the height callback
        // (which triggers a SwiftUI update) can't cause a reload loop.
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: KaTeXAssets.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let height: Binding<CGFloat>
        var loadedHTML: String?

        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [height] result, _ in
                guard let number = (result as? NSNumber)?.doubleValue, number > 0 else { return }
                let value = CGFloat(number)
                if abs(value - height.wrappedValue) > 0.5 { height.wrappedValue = value }
            }
        }
    }
}

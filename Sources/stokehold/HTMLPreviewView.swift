import SwiftUI
import WebKit

/// d253/d418: Dan writes pure markdown normally; HTML is for exceptional
/// preview cases. d418 (Dan, 2026-07-18): JavaScript ENABLED — interactive
/// fleet-generated artifacts (portal mockups, reports with tabs/charts) need
/// script execution to render fully; disabling it left tabs and other JS
/// controls dead in the preview. Content stays confined to the previewed
/// file's own directory as the read-access root (loadFileURL below), and
/// these are the fleet's own generated previews, not untrusted third-party
/// pages loaded from the network.
struct HTMLPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences
        let webView = WKWebView(frame: .zero, configuration: configuration)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // `loadFileURL` (not `load(_:)`) so relative same-directory
        // resources (a sibling image, say) resolve, while still confined
        // to the presentations directory as the read-access root — never
        // wider than the one file being previewed's own folder.
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

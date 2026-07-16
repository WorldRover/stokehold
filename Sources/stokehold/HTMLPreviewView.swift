import SwiftUI
import WebKit

/// d253: Dan writes pure markdown normally; HTML is only for exceptional
/// preview cases. v1 = JavaScript DISABLED — this is loading arbitrary
/// local files from the presentations directory, not trusted first-party
/// content, so there's no reason to grant script execution for a preview
/// surface that only ever needs to render markup.
struct HTMLPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = false
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

import SwiftUI
import WebKit

/// d253/d418: Dan writes pure markdown normally; HTML is for exceptional
/// preview cases. d418 (Dan, 2026-07-18): JavaScript ENABLED — interactive
/// fleet-generated artifacts (portal mockups, reports with tabs/charts) need
/// script execution to render fully; disabling it left tabs and other JS
/// controls dead in the preview. Content stays confined to the previewed
/// file's own directory as the read-access root, and these are the fleet's
/// own generated previews, not untrusted third-party pages loaded from the
/// network.
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
        // d503: `loadFileURL` leaves character-encoding detection to
        // WebKit's own HTML charset-sniffing — with no `<meta charset>`,
        // no BOM, and no HTTP Content-Type header (a bare file:// load),
        // that sniffing falls back to a non-UTF-8 legacy default and every
        // multi-byte UTF-8 sequence (box-drawing chars, em-dashes,
        // checkmarks) renders as mojibake. Fleet-generated presentation
        // fragments (e.g. cartog's mocks) are frequently bare `<style>` +
        // body snippets with no `<head>` at all, so they can't be trusted
        // to self-declare a charset. Read the bytes ourselves and hand
        // WebKit an explicit UTF-8 encoding via `load(_:mimeType:
        // characterEncodingName:baseURL:)` — this bypasses charset
        // sniffing entirely, so the file's own declaration (or lack of
        // one) can no longer matter. `baseURL` stays the file's own
        // directory so a relative same-directory resource (a sibling
        // image, say) still RESOLVES to the right URL.
        //
        // OPEN QUESTION (mate4 cross-review, not yet resolved): unlike
        // `loadFileURL(_:allowingReadAccessTo:)`, this API has no
        // documented equivalent grant of WebContent-process file-read
        // access for that resolved sibling URL — resolving to the right
        // path and actually being allowed to READ it are two different
        // things. Attempted to verify empirically via a headless XCTest
        // (see HTMLPreviewEncodingTests.testSiblingImageResourceStillLoadsViaBaseURL)
        // but discovered the harness itself can't validate this either
        // way — the SAME test fails identically against the untouched,
        // proven-in-production `loadFileURL` call, so a bare `swift test`
        // process apparently can't complete WKWebView subresource fetches
        // at all (no full app bundle / WindowServer context). Today's
        // fleet convention is self-contained HTML (inline CSS/JS/images as
        // data URIs) — no shipped presentation currently references a
        // sibling file — so this is believed low-risk, but genuinely
        // UNVERIFIED for either the old or new code path. Needs a real
        // in-app check (not headless XCTest) before anyone ships a
        // presentation with sibling resource references.
        Self.loadUTF8(fileAt: url, into: webView)
    }

    /// Pulled out of `updateNSView` so a test can drive the exact same
    /// load call against a bare `WKWebView` without standing up SwiftUI.
    static func loadUTF8(fileAt url: URL, into webView: WKWebView) {
        guard let data = try? Data(contentsOf: url) else { return }
        webView.load(
            data,
            mimeType: "text/html",
            characterEncodingName: "utf-8",
            baseURL: url.deletingLastPathComponent()
        )
    }
}

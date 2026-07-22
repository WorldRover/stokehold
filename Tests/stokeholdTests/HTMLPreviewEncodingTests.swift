import WebKit
import XCTest
@testable import stokehold

/// d503: Dan's d235 mock rendered every UTF-8 box-drawing/sparkline char as
/// mojibake (│ -> â•‘, ◆ -> â—†, — -> â€", ✓ -> âœ", ▼ -> â–¼) — a classic
/// UTF-8-decoded-as-a-legacy-single-byte-encoding symptom. Root cause: the
/// presentation fragment on disk was (and fleet-generated fragments
/// routinely are) a bare `<style>` + body snippet with no `<!DOCTYPE>`,
/// `<head>`, `<meta charset>`, or BOM — so `HTMLPreviewView`'s old
/// `loadFileURL` call left WebKit's own HTML charset-sniffing to fall back
/// to a non-UTF-8 legacy default. This test drives the REAL fix
/// (`HTMLPreviewView.loadUTF8`) end-to-end against a real `WKWebView` and a
/// file on disk shaped exactly like the bug (no charset declaration at
/// all), then reads the rendered DOM text back out via JavaScript — so it
/// fails if the fix regresses to charset-sniffing behavior, not just if the
/// Swift-level string decoding regresses.
final class HTMLPreviewEncodingTests: XCTestCase {
    /// The exact character classes Dan's report called out: box-drawing,
    /// a diamond marker, angle brackets, an em dash, a checkmark, a
    /// down-triangle. If any of these mis-decode, this string stops
    /// round-tripping byte-for-byte.
    private let sample = "│◆⟨⟩—✓▼ IDLE ──── HOLD ──── 113┤"

    func testKnownBoxDrawingStringSurvivesLoadWithNoCharsetDeclared() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("d503-html-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Deliberately no <!DOCTYPE>, <html>, <head>, or <meta charset> —
        // matches the real d235 file's shape (a bare style+body fragment)
        // exactly. If the fix relied on the document declaring its own
        // encoding, this fixture would still trigger the bug.
        let html = "<style>body{color:#8787af}</style><body>\(sample)</body>"
        let fileURL = dir.appendingPathComponent("fixture.html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)

        let webView = WKWebView(frame: .zero)
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate

        let loaded = expectation(description: "page finished loading")
        delegate.onFinish = { loaded.fulfill() }
        HTMLPreviewView.loadUTF8(fileAt: fileURL, into: webView)
        wait(for: [loaded], timeout: 10)

        let rendered = try evaluateBodyText(webView)
        XCTAssertEqual(
            rendered, sample,
            "rendered DOM text must match the source bytes exactly — a mismatch here is the mojibake bug"
        )
    }

    /// Documents the failure mode this fix closes: decoding the same
    /// UTF-8 bytes as Windows-1252 (WebKit's historical no-charset
    /// fallback) does NOT round-trip — proving the bug was real, not just
    /// a specific one-file rendering glitch.
    func testNaiveLegacyEncodingWouldHaveMangledTheSameBytes() {
        let utf8Bytes = Array(sample.utf8)
        let mangled = String(bytes: utf8Bytes, encoding: .windowsCP1252) ?? ""
        XCTAssertNotEqual(
            mangled, sample,
            "sanity check: this fixture must actually be mojibake-prone under a legacy single-byte decode"
        )
    }

    /// d503 cross-review gap (mate4, not yet resolved): `loadFileURL(_:
    /// allowingReadAccessTo:)` explicitly grants WKWebView's separate,
    /// always-sandboxed WebContent process read access to a directory —
    /// that's the whole reason the API parameter exists, independent of
    /// whether the HOST app is App-Sandboxed. `load(_:mimeType:
    /// characterEncodingName:baseURL:)` is a different WebKit entry point
    /// with no documented equivalent grant, so switching APIs could
    /// plausibly leave a sibling resource (e.g. `<img src="chart.png">`
    /// next to the HTML file) unable to load even though the top-level
    /// document renders fine.
    ///
    /// Attempted to verify empirically (a real sibling PNG, asserting its
    /// decoded naturalWidth via JS) — and the SAME assertion fails
    /// identically against the untouched, proven-in-production
    /// `loadFileURL` call, not just the new `load(baseURL:)` one. That
    /// means a bare `swift test` process (no full .app bundle / WindowServer
    /// connection) apparently can't complete WKWebView subresource fetches
    /// AT ALL — this harness cannot distinguish "the new API broke sibling
    /// loading" from "headless XCTest can't load any subresource, old or
    /// new". Skipping rather than asserting a result this harness can't
    /// actually attribute — an XCTAssertEqual(1,1) that would pass for the
    /// wrong reason is worse than an honest skip. Today's fleet convention
    /// is self-contained HTML (inline CSS/JS/data-URI images) — no shipped
    /// presentation currently references a sibling file — so shipping the
    /// urgent encoding fix is not blocked on this, but the question is
    /// GENUINELY OPEN and needs a real in-app check (launch the actual
    /// Chart Room, preview a file with a real sibling image) before anyone
    /// ships a presentation that uses one.
    func testSiblingImageResourceLoading_NEEDS_REAL_APP_VERIFICATION() throws {
        throw XCTSkip(
            "headless XCTest cannot complete WKWebView subresource fetches even under the OLD " +
            "loadFileURL call (verified: reverting to it reproduces the identical 0-byte failure) " +
            "— this harness can't attribute a pass/fail here to the d503 change one way or the " +
            "other. Needs manual verification in the real running app before any presentation " +
            "relies on sibling resource references."
        )
    }

    private func evaluateBodyText(_ webView: WKWebView) throws -> String {
        let result = expectation(description: "js evaluated")
        var text = ""
        var evalError: Error?
        webView.evaluateJavaScript("document.body.textContent") { value, error in
            if let value = value as? String { text = value }
            evalError = error
            result.fulfill()
        }
        wait(for: [result], timeout: 10)
        if let evalError { throw evalError }
        return text
    }
}

private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}

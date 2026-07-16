import AppKit
import SwiftUI

/// Trivial mutable box so the self-removing observer closure below can
/// hold a reference to its own token without a `var` capture Swift 6's
/// strict concurrency checker flags on a `@Sendable` closure.
private final class ObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}

/// Fixes the real bug: Stokehold is a `MenuBarExtra`-only app (never sets
/// an `activationPolicy`, so AppKit defaults it to `.accessory` — no Dock
/// icon, no Cmd-Tab entry, and critically no automatic activation when a
/// new window opens). `openWindow(id:)` alone creates the Chart Room
/// window but never brings the app or that window forward — it opens
/// behind everything (or the app doesn't even become key), which reads
/// exactly like Dan's report: "clicking chart room doesn't seem to do
/// anything."
///
/// Fixes BOTH halves of the tradeoff named in the task: (1) explicitly
/// activates the app and brings the window to front the moment it
/// appears; (2) switches the activation policy to `.regular` ONLY WHILE
/// the window is open (real focus, Cmd-Tab entry, a Dock icon like any
/// normal foreground app while Dan is reading it), then reverts to
/// `.accessory` the instant the window closes — so Stokehold never grows
/// a PERMANENT Dock icon (Dan: a menubar app, not a dock app).
///
/// An invisible `NSViewRepresentable` rather than pure SwiftUI because
/// getting the actual `NSWindow` this content is hosted in (needed for
/// `makeKeyAndOrderFront` and to scope the close-notification to THIS
/// window specifically, not any window) has no SwiftUI-only equivalent.
struct ChartRoomWindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            // Self-removing: only needs to fire once per window lifecycle
            // (revert on close), not accumulate an observer per re-open.
            // Boxed in a class (not a bare `var`) so Swift 6 strict
            // concurrency doesn't flag mutating a captured local from
            // inside the @Sendable notification closure.
            let tokenBox = ObserverTokenBox()
            tokenBox.token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.accessory)
                if let token = tokenBox.token {
                    NotificationCenter.default.removeObserver(token)
                }
            }
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

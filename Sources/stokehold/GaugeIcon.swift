import AppKit
import SwiftUI

enum GaugeIcon {
    static func menubarTemplateImage() -> NSImage {
        let image = resourceImage(named: "menubar-gauge") ?? fallbackGaugeImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func appIcon(needsDan: Bool) -> NSImage {
        let base = resourceImage(named: "appicon-gauge") ?? fallbackGaugeImage(size: NSSize(width: 512, height: 512))
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        if needsDan {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 372, y: 356, width: 92, height: 92)).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 372, y: 356, width: 92, height: 92))
            ring.lineWidth = 8
            ring.stroke()
        }
        image.unlockFocus()
        return image
    }

    static func installAppIcon(needsDan: Bool) {
        let image = appIcon(needsDan: needsDan)
        NSApplication.shared.applicationIconImage = image
        NSApplication.shared.dockTile.display()
    }

    private static func resourceImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    private static func fallbackGaugeImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.labelColor.setStroke()
        let bounds = NSRect(origin: .zero, size: size).insetBy(dx: size.width * 0.12, dy: size.height * 0.12)
        let path = NSBezierPath(ovalIn: bounds)
        path.lineWidth = max(2, size.width * 0.08)
        path.stroke()
        let center = NSPoint(x: size.width * 0.5, y: size.height * 0.48)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: size.width * 0.72, y: size.height * 0.72))
        needle.lineWidth = max(2, size.width * 0.07)
        needle.stroke()
        NSBezierPath(ovalIn: NSRect(x: center.x - size.width * 0.07, y: center.y - size.width * 0.07, width: size.width * 0.14, height: size.width * 0.14)).fill()
        image.unlockFocus()
        return image
    }
}

import AppKit
import SwiftUI

enum GaugeIcon {
    private static let appIconSize = NSSize(width: 512, height: 512)
    private static let appIconArtworkScale: CGFloat = 0.80
    private static let appIconBadgeDiameter: CGFloat = 104
    private static let appIconBadgeRingWidth: CGFloat = 8

    static func menubarTemplateImage() -> NSImage {
        let image = resourceImage(named: "menubar-gauge") ?? fallbackGaugeImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func appIcon(needsDan: Bool) -> NSImage {
        let base = resourceImage(named: "appicon-gauge") ?? fallbackGaugeImage(size: appIconSize)
        let size = appIconSize
        let image = NSImage(size: size)
        image.lockFocus()
        let inset = size.width * ((1 - appIconArtworkScale) / 2)
        let artworkRect = NSRect(origin: NSPoint(x: inset, y: inset),
                                 size: NSSize(width: size.width - inset * 2, height: size.height - inset * 2))
        base.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1)
        if needsDan {
            let badgeRect = NSRect(
                x: artworkRect.maxX - appIconBadgeDiameter / 2,
                y: artworkRect.maxY - appIconBadgeDiameter / 2,
                width: appIconBadgeDiameter,
                height: appIconBadgeDiameter
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(ovalIn: badgeRect)
            ring.lineWidth = appIconBadgeRingWidth
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

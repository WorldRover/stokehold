import AppKit
import SwiftUI

@MainActor
enum GaugeIcon {
    private static let appIconSize = NSSize(width: 512, height: 512)
    private static let appIconArtworkScale: CGFloat = 0.80
    private static let appIconBadgeDiameter: CGFloat = 104
    private static let appIconBadgeRingWidth: CGFloat = 8
    private static var loggedResourceFailures = Set<String>()
    private static var resourceCache: [String: NSImage] = [:]

    static func menubarTemplateImage() -> NSImage {
        let image = resourceImage(named: "menubar-gauge") ?? fallbackGaugeImage(size: NSSize(width: 18, height: 18), label: "menubar fallback")
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func appIcon(needsDan: Bool) -> NSImage {
        let base = resourceImage(named: "appicon-gauge") ?? fallbackGaugeImage(size: appIconSize, label: "app icon fallback")
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
        guard image.containsVisiblePixels else {
            log("refusing to install blank app icon; keeping existing application icon")
            return
        }
        NSApplication.shared.applicationIconImage = image
        NSApplication.shared.dockTile.display()
        log("installed app icon needsDan=\(needsDan)")
    }

    private static func resourceImage(named name: String) -> NSImage? {
        if let cached = resourceCache[name]?.copy() as? NSImage {
            return cached
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            logResourceFailure(name, detail: "resource URL or NSImage load failed")
            return nil
        }
        guard image.isValid, image.containsVisiblePixels else {
            logResourceFailure(name, detail: "loaded image is invalid or blank")
            return nil
        }
        resourceCache[name] = image
        log("loaded \(name).svg from \(url.path)")
        return image
    }

    private static func fallbackGaugeImage(size: NSSize, label: String) -> NSImage {
        log("using \(label) gauge drawing")
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

    private static func logResourceFailure(_ name: String, detail: String) {
        if loggedResourceFailures.insert(name).inserted {
            log("FAILED to load \(name).svg: \(detail)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[stokehold] GaugeIcon: \(message)\n".utf8))
    }
}

private extension NSImage {
    var containsVisiblePixels: Bool {
        guard let tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffRepresentation),
              let cgImage = rep.cgImage else {
            return false
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return false }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: bytesPerPixel).contains { pixels[$0] > 0 }
    }
}

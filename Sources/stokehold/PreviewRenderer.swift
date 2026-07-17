import AppKit
import SwiftUI

/// Dev utility (d382): `.build/debug/stokehold render-previews [outdir]`
/// renders the REAL dropdown and menubar-label views offscreen to PNGs and
/// exits before the MenuBarExtra scene ever starts — no second menubar item,
/// no display interaction needed. Exists so design proposals sent to Dan are
/// screenshots of the shipping views with sample data, not hand-drawn
/// mockups that can drift from the implementation.
@MainActor
enum PreviewRenderer {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "render-previews") else { return }
        let outPath = args.indices.contains(flagIndex + 1)
            ? args[flagIndex + 1]
            : FileManager.default.currentDirectoryPath
        let dir = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        renderAll(to: dir)
        exit(0)
    }

    private static func renderAll(to dir: URL) {
        let reading = BoilerReading(
            cpuPercent: 38, ramPercent: 61, load1: 2.1,
            fleetCPUPercent: 14, fleetRAMPercent: 9
        )

        let busyFleet = FleetSnapshot(
            fleetCapacity: [
                "working": ["helm", "mate4", "mate9", "mate12", "arch"],
                "blocked": ["mate6"],
                "standby_headless": ["stoker", "signal"],
            ],
            dispatchCount: 7,
            docketRows: sampleRows(needsDan: 3, others: 20)
        )
        let quietFleet = FleetSnapshot(
            fleetCapacity: [
                "working": ["helm", "mate4"],
                "standby_headless": ["stoker", "signal"],
            ],
            dispatchCount: 0,
            docketRows: sampleRows(needsDan: 0, others: 12)
        )

        for (scheme, suffix) in [(ColorScheme.dark, "dark"), (ColorScheme.light, "light")] {
            let bg = scheme == .dark ? Color(white: 0.13) : Color(white: 0.97)
            save(
                DropdownView(reading: reading, fleet: busyFleet, fleetStale: false, chartRoomUnseenCount: 2)
                    .background(bg)
                    .environment(\.colorScheme, scheme),
                "dropdown-busy-\(suffix)", to: dir
            )
            save(
                DropdownView(reading: reading, fleet: quietFleet, fleetStale: false, chartRoomUnseenCount: 0)
                    .background(bg)
                    .environment(\.colorScheme, scheme),
                "dropdown-quiet-\(suffix)", to: dir
            )
        }

        // Menubar label states, rendered on a dark strip approximating the
        // menubar; scale 4 so the ~18pt label is legible in a proposal doc.
        for (count, name) in [(0, "menubar-label-dan-0"), (3, "menubar-label-dan-3")] {
            save(
                MenuBarGaugeLabel(reading: reading, chartRoomUnseenCount: 0, needsDanCount: count)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.13))
                    .environment(\.colorScheme, .dark),
                name, to: dir, scale: 4
            )
        }
    }

    private static func sampleRows(needsDan: Int, others: Int) -> [DocketRow] {
        let dan = (0..<needsDan).map { i in
            DocketRow(id: "d\(400 + i)", pri: "H", text: "sample dan-owned item \(i)",
                      owner: "dan", linearId: "", needsDan: true)
        }
        let rest = (0..<others).map { i in
            DocketRow(id: "d\(500 + i)", pri: "M", text: "sample fleet item \(i)",
                      owner: "mate\(i % 9)", linearId: "", needsDan: false)
        }
        return dan + rest
    }

    private static func save<Content: View>(
        _ view: Content, _ name: String, to dir: URL, scale: CGFloat = 2
    ) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else {
            print("render FAILED: \(name)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("png encode FAILED: \(name)")
            return
        }
        let url = dir.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            print("wrote \(url.path)")
        } catch {
            print("write FAILED: \(url.path) — \(error)")
        }
    }
}

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

        // The dropdown against the LIVE fleet (real console poll), plus the
        // Chart Room window with the live docket — so proposals can show
        // today's actual state, not only synthetic sample data. Skipped
        // silently if the console subprocess fails (e.g. no fleet running).
        if let live = FleetConsole.sample() {
            save(
                DropdownView(reading: reading, fleet: live, fleetStale: false, chartRoomUnseenCount: 0)
                    .background(Color(white: 0.13))
                    .environment(\.colorScheme, .dark),
                "dropdown-live-dark", to: dir
            )
            // The docket panel rebuilt eagerly from the REAL row view —
            // NavigationSplitView, segmented Picker, and LazyVStack all
            // render placeholders under an offscreen ImageRenderer, so the
            // panel chrome is approximated; the rows are the shipping code.
            let chartRoom = ChartRoomView(model: PresentationsModel(), docketRows: live.docketRows)
            let danRows = live.docketRows.filter(\.needsDan)
            save(
                VStack(alignment: .leading, spacing: 0) {
                    Text("Docket — Dan")
                        .font(.headline)
                        .padding([.horizontal, .top])
                        .padding(.bottom, 8)
                    ForEach(danRows) { row in
                        chartRoom.docketRowView(row)
                        Divider()
                    }
                }
                .frame(width: 760)
                .background(Color(white: 0.13))
                .environment(\.colorScheme, .dark),
                "docket-panel-live-dark", to: dir
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
        for value in [0, 7, 42, 100] {
            let valueReading = BoilerReading(
                cpuPercent: Double(value), ramPercent: reading.ramPercent, load1: reading.load1,
                fleetCPUPercent: reading.fleetCPUPercent, fleetRAMPercent: reading.fleetRAMPercent
            )
            save(
                MenuBarGaugeLabel(reading: valueReading, chartRoomUnseenCount: 0, needsDanCount: 3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.13))
                    .environment(\.colorScheme, .dark),
                "menubar-label-value-\(value)", to: dir, scale: 4
            )
        }
        save(GaugeIcon.appIcon(needsDan: false), "app-icon-dan-0", to: dir)
        save(GaugeIcon.appIcon(needsDan: true), "app-icon-dan-3", to: dir)
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

    private static func save(_ image: NSImage, _ name: String, to dir: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
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

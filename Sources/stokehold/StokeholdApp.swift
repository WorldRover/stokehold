import SwiftUI

@MainActor
final class BoilerModel: ObservableObject {
    @Published var reading = BoilerReading(
        cpuPercent: 0, ramPercent: 0, load1: 0,
        fleetCPUPercent: 0, fleetRAMPercent: 0
    )
    @Published var fleet: FleetSnapshot?
    // d191: `FleetConsole.sample()` returns nil on any subprocess failure
    // (non-zero exit, unparseable JSON) and the loop below used to just skip
    // the update — leaving `fleet` frozen on whatever snapshot last
    // succeeded, with no indication it had gone stale. Track that here so
    // the UI can say so instead of quietly showing old crew state as live.
    @Published var fleetStale: Bool = false

    private var loop: Task<Void, Never>?
    private var fleetLoop: Task<Void, Never>?

    init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let sample = await Task.detached { BoilerMetrics.sample() }.value
                guard let self else { return }
                self.reading = sample
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        // Fleet-console data comes from a python subprocess (read-only reuse
        // of console.py) rather than a process scan, so it's polled on its
        // own slower cadence — no reason to pay that spawn cost every 2s.
        fleetLoop = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await Task.detached { FleetConsole.sample() }.value
                guard let self else { return }
                if let snapshot {
                    self.fleet = snapshot
                    self.fleetStale = false
                } else if self.fleet != nil {
                    self.fleetStale = true
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

@main
struct StokeholdApp: App {
    init() {
        // d382 dev utility: `stokehold render-previews [outdir]` renders the
        // dropdown/label views to PNGs and exits before any scene starts.
        PreviewRenderer.runIfRequested()
    }

    @StateObject private var model = BoilerModel()
    // d253: owned at the App level (not inside ChartRoomView) so the
    // unseen-count BADGE on the menubar icon stays live even while the
    // Chart Room window itself is closed — the model's poll loop keeps
    // running either way, same as `BoilerModel`'s own gauges.
    @StateObject private var presentationsModel = PresentationsModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            DropdownView(
                reading: model.reading,
                fleet: model.fleet,
                fleetStale: model.fleetStale,
                chartRoomUnseenCount: presentationsModel.unseenCount
            ) {
                openWindow(id: "chart-room")
            }
        } label: {
            MenuBarGaugeLabel(
                reading: model.reading,
                chartRoomUnseenCount: presentationsModel.unseenCount,
                needsDanCount: model.fleet?.needsDanOpenCount ?? 0
            )
        }

        Window("Chart Room", id: "chart-room") {
            // d298 rework: docketRows reuses BoilerModel's EXISTING
            // FleetConsole poll (the same signal FleetSummaryView's
            // dropdown row already reads) rather than a second independent
            // subprocess-polling loop for the same data.
            ChartRoomView(model: presentationsModel, docketRows: model.fleet?.docketRows ?? [])
        }
    }
}

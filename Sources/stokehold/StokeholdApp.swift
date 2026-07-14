import SwiftUI

@MainActor
final class BoilerModel: ObservableObject {
    @Published var reading = BoilerReading(
        cpuPercent: 0, ramPercent: 0, load1: 0,
        fleetCount: 0, fleetCPUPercent: 0, fleetRAMPercent: 0
    )
    @Published var fleet: FleetSnapshot?

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
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

@main
struct StokeholdApp: App {
    @StateObject private var model = BoilerModel()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text("stokehold")
                    .font(.headline)

                HStack(spacing: 16) {
                    PressureGauge(label: "CPU", value: model.reading.cpuPercent, dangerThreshold: 80)
                    PressureGauge(label: "RAM", value: model.reading.ramPercent, dangerThreshold: 85)
                    PressureGauge(label: "LOAD", value: min(model.reading.load1 * 25, 100), dangerThreshold: 80)
                }

                Divider()

                Text(BlackGang.statusLine(for: model.reading))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                FleetSummaryView(fleet: model.fleet)
            }
            .padding()
            .frame(width: 300)
        } label: {
            MenuBarGaugeLabel(reading: model.reading)
        }
    }
}

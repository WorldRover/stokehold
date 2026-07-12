import SwiftUI

@MainActor
final class BoilerModel: ObservableObject {
    @Published var reading = BoilerReading(
        cpuPercent: 0, ramPercent: 0, load1: 0,
        fleetCount: 0, fleetCPUPercent: 0, fleetRAMPercent: 0
    )

    private var loop: Task<Void, Never>?

    init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let sample = await Task.detached { BoilerMetrics.sample() }.value
                guard let self else { return }
                self.reading = sample
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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
            }
            .padding()
            .frame(width: 240)
        } label: {
            MenuBarGaugeLabel(reading: model.reading)
        }
    }
}

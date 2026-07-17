import SwiftUI

/// The MenuBarExtra dropdown's full content, extracted from the App scene
/// (d382) so the SAME view the live dropdown shows can also be rendered
/// offscreen by `PreviewRenderer` for design screenshots — no drift between
/// what Dan is sent as a mockup and what actually ships.
struct DropdownView: View {
    let reading: BoilerReading
    let fleet: FleetSnapshot?
    let fleetStale: Bool
    let chartRoomUnseenCount: Int
    var openChartRoom: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("stokehold")
                .font(.headline)

            HStack(spacing: 12) {
                PressureGauge(label: "CPU", value: reading.cpuPercent, dangerThreshold: 80)
                PressureGauge(label: "RAM", value: reading.ramPercent, dangerThreshold: 85)
                PressureGauge(label: "LOAD", value: min(reading.load1 * 25, 100), dangerThreshold: 80)
            }

            Divider()

            Text(BlackGang.statusLine(for: reading, hands: fleet?.crewCount))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            FleetSummaryView(fleet: fleet, stale: fleetStale, openChartRoom: openChartRoom)

            Divider()

            Button(action: openChartRoom) {
                HStack {
                    Text("Chart Room")
                    Spacer()
                    if chartRoomUnseenCount > 0 {
                        Text("\(chartRoomUnseenCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 250)
    }
}

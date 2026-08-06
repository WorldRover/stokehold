import SwiftUI

/// The MenuBarExtra dropdown's full content, extracted from the App scene
/// (d382) so the SAME view the live dropdown shows can also be rendered
/// offscreen by `PreviewRenderer` for design screenshots — no drift between
/// what Dan is sent as a mockup and what actually ships.
struct DropdownView: View {
    let reading: BoilerReading
    let fleet: FleetSnapshot?
    let fleetStale: Bool
    var fleetError: FleetConsoleError?
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

            // #17: hands below, not the whole roster — a down seat isn't
            // shovelling. The roster total still shows in FleetSummaryView's
            // "N crew" line just below.
            Text(BlackGang.statusLine(
                for: reading,
                hands: fleet?.handsCount,
                consoleFailed: fleetError != nil
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            FleetSummaryView(
                fleet: fleet,
                stale: fleetStale,
                error: fleetError,
                openChartRoom: openChartRoom
            )

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

import SwiftUI

/// The dropdown's fleet section — missions, ALL crew activity (including
/// headless mates, which the CPU/RAM gauges' process scan can miss), pending
/// Dispatches, items needing Dan, and the review shelf. Renders from a
/// `FleetSnapshot` (see `FleetConsole.swift`); shows nothing while the first
/// sample is still in flight rather than a misleading zeroed-out section.
struct FleetSummaryView: View {
    let fleet: FleetSnapshot?

    var body: some View {
        if let fleet {
            VStack(alignment: .leading, spacing: 6) {
                Text("Fleet")
                    .font(.headline)

                crewLine(for: fleet)

                summaryRow(count: fleet.missions.count, label: "active mission", items: fleet.missions)
                summaryRow(count: fleet.dispatchCount, label: "pending dispatch")
                summaryRow(count: fleet.needsDan.count, label: "item needs Dan", items: fleet.needsDan, highlight: true)
                summaryRow(count: fleet.reviewShelf.count, label: "on the review shelf", items: fleet.reviewShelf)
            }
        } else {
            Text("Fleet — reading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func crewLine(for fleet: FleetSnapshot) -> some View {
        let working = fleet.fleetCapacity["working"]?.count ?? 0
        let blocked = fleet.blockedCount
        let headless = fleet.headlessStandbyCount
        return Text("\(fleet.crewCount) crew — \(working) working · \(blocked) blocked · \(headless) headless standby")
            .font(.caption)
            .foregroundStyle(blocked > 0 ? .red : .secondary)
    }

    /// A count line, with up to 2 preview items underneath when present —
    /// bounded so the dropdown can't grow into a full console dump.
    @ViewBuilder
    private func summaryRow(count: Int, label: String, items: [String] = [], highlight: Bool = false) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) \(label)\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(highlight ? .orange : .primary)
                ForEach(items.prefix(2), id: \.self) { item in
                    Text("· \(item)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if items.count > 2 {
                    Text("+ \(items.count - 2) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

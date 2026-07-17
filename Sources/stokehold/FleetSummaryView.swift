import SwiftUI

/// The dropdown's fleet section — ALL crew activity (including headless
/// mates, which the CPU/RAM gauges' process scan can miss), pending
/// Dispatches, items needing Dan, and the review shelf. Renders from a
/// `FleetSnapshot` (see `FleetConsole.swift`); shows nothing while the first
/// sample is still in flight rather than a misleading zeroed-out section.
///
/// Rows are built into a plain array and rendered via `ForEach` rather than a
/// stack of `if count > 0 { ... }` siblings — an empty conditional branch can
/// still reserve a VStack spacing slot, which is exactly the dead vertical
/// gap Dan flagged (d184). Hidden (zero-count) sections are dropped from the
/// array entirely, so nothing but real content ever takes up space.
struct FleetSummaryView: View {
    let fleet: FleetSnapshot?
    let stale: Bool

    private struct Row: Identifiable {
        let id: String
        let count: Int
        let label: String
        let items: [String]
        let highlight: Bool
    }

    var body: some View {
        if let fleet {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Fleet")
                        .font(.caption)
                        .fontWeight(.semibold)
                    // d191: the last successful sample can be arbitrarily old
                    // if the console subprocess keeps failing — say so rather
                    // than let a frozen crew line read as live state.
                    if stale {
                        Text("(stale)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                crewLine(for: fleet)

                ForEach(rows(for: fleet)) { row in
                    rowView(row)
                }
            }
        } else {
            Text("Fleet — reading…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func rows(for fleet: FleetSnapshot) -> [Row] {
        [
            Row(id: "dispatch", count: fleet.dispatchCount, label: "pending dispatch", items: [], highlight: false),
            Row(id: "needsDan", count: fleet.needsDan.count, label: "item needs Dan", items: fleet.needsDan, highlight: true),
            Row(id: "review", count: fleet.reviewShelf.count, label: "on the review shelf", items: fleet.reviewShelf, highlight: false),
        ].filter { $0.count > 0 }
    }

    private func crewLine(for fleet: FleetSnapshot) -> some View {
        let working = fleet.fleetCapacity["working"]?.count ?? 0
        let blocked = fleet.blockedCount
        let headless = fleet.headlessStandbyCount
        return Text("\(fleet.crewCount) crew — \(working) working · \(blocked) blocked · \(headless) headless standby")
            .font(.caption2)
            .foregroundStyle(blocked > 0 ? .red : .secondary)
    }

    /// A count line, with up to 2 preview items underneath when present —
    /// bounded so the dropdown can't grow into a full console dump.
    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(row.count) \(row.label)\(row.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(row.highlight ? .orange : .primary)
            ForEach(row.items.prefix(2), id: \.self) { item in
                Text("· \(item)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if row.items.count > 2 {
                Text("+ \(row.items.count - 2) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

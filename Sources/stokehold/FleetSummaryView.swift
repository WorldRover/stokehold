import SwiftUI

/// The dropdown's fleet section — COUNTS-ONLY (d382, Dan's ruling): the
/// dropdown is a GLANCE surface, not a reading surface. Quick-access counts,
/// no item lists, no item text at all — the Chart Room is where detail
/// lives, so every row doubles as a click-through into it.
///
/// Needs-Dan is the hero row: it's the one count that means "Dan has to act,"
/// so it renders bigger and hotter than everything else. Its count is
/// `FleetSnapshot.needsDanOpenCount` — the SAME docket-derived
/// dan-owned-open-items signal the Chart Room's Docket panel and the menubar
/// dot read (one derivation, three surfaces, never disagreeing), NOT a
/// second independently-derived "needs Dan" list.
///
/// Zero-count rows drop entirely (d184 zero-drops convention — same rule the
/// menubar dot follows): nothing but real signal ever takes up space. The
/// crew line always shows; "who's below" is state, not a to-do count.
struct FleetSummaryView: View {
    let fleet: FleetSnapshot?
    let stale: Bool
    /// Injected by the App scene (`openWindow` lives there); defaults to a
    /// no-op so the view stays constructible in previews/renders.
    var openChartRoom: () -> Void = {}

    var body: some View {
        if let fleet {
            VStack(alignment: .leading, spacing: 5) {
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

                if fleet.needsDanOpenCount > 0 {
                    needsDanRow(count: fleet.needsDanOpenCount)
                }

                crewLine(for: fleet)

                if fleet.dispatchCount > 0 {
                    countRow(count: fleet.dispatchCount,
                             label: "pending dispatch\(fleet.dispatchCount == 1 ? "" : "es")",
                             help: "Open the Chart Room")
                }
                if fleet.openDocketCount > 0 {
                    countRow(count: fleet.openDocketCount,
                             label: "open docket item\(fleet.openDocketCount == 1 ? "" : "s")",
                             help: "Open the Chart Room docket panel")
                }
            }
        } else {
            Text("Fleet — reading…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The hero: the only row whose count means "Dan has to act." Bigger,
    /// bolder, hotter than the secondary counts; click lands in the Chart
    /// Room, whose Docket panel already defaults to the Dan-only filter.
    private func needsDanRow(count: Int) -> some View {
        Button(action: openChartRoom) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("\(count) need\(count == 1 ? "s" : "") Dan")
                    .font(.callout)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .foregroundStyle(.orange)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the Chart Room docket panel")
    }

    /// One line, always visible — "who's below" is state, not a to-do
    /// count. Only the blocked segment turns red (and drops at 0, d184),
    /// so a single blocked mate doesn't paint the whole line as an alarm.
    private func crewLine(for fleet: FleetSnapshot) -> some View {
        var line = Text("\(fleet.crewCount) crew · \(fleet.workingCount) working")
        if fleet.blockedCount > 0 {
            // `foregroundColor` (not `foregroundStyle`): the Text-returning
            // overload needed for concatenation exists back to our macOS 13
            // deployment target; the style variant is 14.0+.
            line = line + Text(" · \(fleet.blockedCount) blocked").foregroundColor(.red)
        }
        if fleet.headlessStandbyCount > 0 {
            line = line + Text(" · \(fleet.headlessStandbyCount) standby")
        }
        return line
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// A secondary count row: quick-access click-through, no item text ever.
    private func countRow(count: Int, label: String, help: String) -> some View {
        Button(action: openChartRoom) {
            HStack(spacing: 0) {
                Text("\(count) ")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

import Foundation

/// Maritime-steampunk copy, keyed off machine + fleet pressure.
enum BlackGang {
    static func glanceLabel(for reading: BoilerReading) -> String {
        "\(Int(reading.cpuPercent.rounded())) psi"
    }

    /// The SF Symbol whose needle position best tracks `percent` — the
    /// `gauge.with.dots.needle.*percent` family only ships discrete steps
    /// (0/33/50/67/100, verified present on this system), so this picks the
    /// nearest one rather than pretending to a continuous needle position.
    static func gaugeSymbolName(for percent: Double) -> String {
        let steps: [(Double, String)] = [
            (0, "gauge.with.dots.needle.0percent"),
            (33, "gauge.with.dots.needle.33percent"),
            (50, "gauge.with.dots.needle.50percent"),
            (67, "gauge.with.dots.needle.67percent"),
            (100, "gauge.with.dots.needle.100percent"),
        ]
        return steps.min(by: { abs($0.0 - percent) < abs($1.0 - percent) })!.1
    }

    /// `hands` is the console.py-derived crew count (`FleetSnapshot.crewCount`
    /// via `FleetConsole.sample()`), NOT `BoilerReading` — see the d229-
    /// followup note on `BoilerReading` for why. `nil` means the first
    /// console sample hasn't landed yet (cold start, same convention
    /// `FleetSummaryView` already uses for its own "reading…" state) —
    /// deliberately not defaulted to 0, which would misread as "genuinely no
    /// hands" instead of "not sampled yet."
    static func statusLine(for reading: BoilerReading, hands: Int?) -> String {
        guard let hands else {
            return "Reading the fleet…"
        }
        switch (hands, reading.cpuPercent) {
        case (0, ..<15):
            return "Cold boilers, crew ashore."
        case (0, _):
            return "No hands below — she's idling on her own."
        case (_, 80...):
            return "\(hands) hand\(hands == 1 ? "" : "s") shovelling hard — boilers in the red."
        case (_, 45..<80):
            return "\(hands) hand\(hands == 1 ? "" : "s") at the boilers, stoking steady."
        default:
            return "\(hands) hand\(hands == 1 ? "" : "s") below, boilers banked low."
        }
    }
}

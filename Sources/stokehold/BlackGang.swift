import Foundation

/// Maritime-steampunk copy, keyed off machine + fleet pressure.
enum BlackGang {
    static func glanceLabel(for reading: BoilerReading) -> String {
        "\(Int(reading.cpuPercent.rounded())) psi"
    }

    static func statusLine(for reading: BoilerReading) -> String {
        switch (reading.fleetCount, reading.cpuPercent) {
        case (0, ..<15):
            return "Cold boilers, crew ashore."
        case (0, _):
            return "No hands below — she's idling on her own."
        case (_, 80...):
            return "\(reading.fleetCount) hand\(reading.fleetCount == 1 ? "" : "s") shovelling hard — boilers in the red."
        case (_, 45..<80):
            return "\(reading.fleetCount) hand\(reading.fleetCount == 1 ? "" : "s") at the boilers, stoking steady."
        default:
            return "\(reading.fleetCount) hand\(reading.fleetCount == 1 ? "" : "s") below, boilers banked low."
        }
    }
}

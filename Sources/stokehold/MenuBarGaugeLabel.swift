import SwiftUI

/// The macOS status-bar (menubar) item: a live brass gauge glyph whose needle
/// tracks `cpuPercent`, plus the "NN psi" readout — replaces the old flat
/// `"NN psi"` text label (Dan: "a bit boring looking, add any pizzazz?").
/// Reuses PressureGauge's CPU danger threshold (80) rather than a second
/// copy of the redline cutoff.
struct MenuBarGaugeLabel: View {
    let reading: BoilerReading
    // d253: unseen Chart Room presentations — surfaced right on the
    // menubar item itself (Dan's ask) rather than only inside the
    // dropdown, so a new arrival is visible without opening the menu at
    // all. 0 renders nothing, matching `FleetSummaryView`'s own
    // zero-count-drops-entirely convention (d184) rather than a
    // permanently-visible "0".
    var chartRoomUnseenCount: Int = 0

    private static let dangerThreshold: Double = 80

    private var isRedline: Bool { reading.cpuPercent >= Self.dangerThreshold }

    var body: some View {
        HStack(spacing: 3) {
            if isRedline {
                // Redline accent: a small flame alongside the gauge — menubar
                // items are historically forced to TEMPLATE (monochrome)
                // rendering, so the shape/glyph itself is what has to carry
                // "hot," not just color; the bold number below carries it too.
                Image(systemName: "flame.fill")
                    .foregroundStyle(.red)
            }
            Image(systemName: BlackGang.gaugeSymbolName(for: reading.cpuPercent))
                .foregroundStyle(isRedline ? .red : .primary)
            Text(BlackGang.glanceLabel(for: reading))
                .monospacedDigit()
                .fontWeight(isRedline ? .bold : .regular)
            if chartRoomUnseenCount > 0 {
                Text("\(chartRoomUnseenCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
        }
    }
}

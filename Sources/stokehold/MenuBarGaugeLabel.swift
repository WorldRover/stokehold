import SwiftUI

/// The macOS status-bar (menubar) item: a live brass gauge glyph whose needle
/// tracks `cpuPercent`, plus the "NN psi" readout — replaces the old flat
/// `"NN psi"` text label (Dan: "a bit boring looking, add any pizzazz?").
/// Reuses PressureGauge's CPU danger threshold (80) rather than a second
/// copy of the redline cutoff.
struct MenuBarGaugeLabel: View {
    let reading: BoilerReading

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
        }
    }
}

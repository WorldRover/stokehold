import SwiftUI

/// The macOS status-bar (menubar) item: a live brass gauge glyph whose needle
/// tracks `cpuPercent`, plus the "NN psi" readout — replaces the old flat
/// `"NN psi"` text label (Dan: "a bit boring looking, add any pizzazz?").
/// Uses hysteresis around the redline threshold: flame turns on at 90 and
/// turns back off below 80, so a noisy sample cannot flicker the menubar.
struct MenuBarGaugeLabel: View {
    let reading: BoilerReading
    // d253: unseen Chart Room presentations — surfaced right on the
    // menubar item itself (Dan's ask) rather than only inside the
    // dropdown, so a new arrival is visible without opening the menu at
    // all. 0 renders nothing, matching `FleetSummaryView`'s own
    // zero-count-drops-entirely convention (d184) rather than a
    // permanently-visible "0".
    var chartRoomUnseenCount: Int = 0
    // d382: OPEN dan-owned docket items (`FleetSnapshot.needsDanOpenCount`
    // — the same single derivation the dropdown's hero row reads). Distinct
    // from the d253 badge above in both meaning and lifecycle: that one
    // counts unseen Chart Room arrivals and clears on view; this one
    // reflects open docket items owned by Dan and clears only when they
    // close. Rendered as a DOT on the gauge glyph, not a second number —
    // menubar template rendering is monochrome, so the SHAPE (dot present
    // vs absent) is what carries the signal, not its color. 0 renders
    // nothing (d184 zero-drops).
    var needsDanCount: Int = 0

    private static let redlineOnThreshold: Double = 90
    private static let redlineOffThreshold: Double = 80
    private static let glyphFrame: CGFloat = 18
    private static let glyphDrawSize: CGFloat = 16
    private static let needsDanDotSize: CGFloat = 5.5
    private static let readoutWidth: CGFloat = 60
    private static let redlineSlotWidth: CGFloat = 10

    @State private var redlineActive = false

    init(reading: BoilerReading, chartRoomUnseenCount: Int = 0, needsDanCount: Int = 0) {
        self.reading = reading
        self.chartRoomUnseenCount = chartRoomUnseenCount
        self.needsDanCount = needsDanCount
        self._redlineActive = State(initialValue: reading.cpuPercent >= Self.redlineOnThreshold)
    }

    var body: some View {
        HStack(spacing: 3) {
            // Keep this slot reserved even when hidden; otherwise crossing
            // the redline threshold shifts the gauge's menubar position.
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.red)
                .opacity(redlineActive ? 1 : 0)
                .frame(width: Self.redlineSlotWidth, height: Self.glyphFrame)
                .clipped()
            ZStack(alignment: .topTrailing) {
                Image(nsImage: GaugeIcon.menubarTemplateImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.glyphDrawSize, height: Self.glyphDrawSize)
                    .foregroundStyle(.primary)
                if needsDanCount > 0 {
                    Circle()
                        .fill(.orange)
                        .frame(width: Self.needsDanDotSize, height: Self.needsDanDotSize)
                        .offset(x: 2.25, y: -1.5)
                    }
            }
            .frame(width: Self.glyphFrame, height: Self.glyphFrame)
            Text(BlackGang.glanceLabel(for: reading))
                .monospacedDigit()
                .lineLimit(1)
                .fontWeight(redlineActive ? .bold : .regular)
                .frame(width: Self.readoutWidth, alignment: .leading)
            if chartRoomUnseenCount > 0 {
                Text("\(chartRoomUnseenCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
        }
        .onAppear { updateRedline(for: reading.cpuPercent) }
        .onChange(of: reading.cpuPercent) { value in
            updateRedline(for: value)
        }
    }

    private func updateRedline(for value: Double) {
        if value >= Self.redlineOnThreshold {
            redlineActive = true
        } else if value < Self.redlineOffThreshold {
            redlineActive = false
        }
    }
}

import SwiftUI

/// The macOS status-bar (menubar) item: a live brass gauge glyph whose needle
/// tracks `cpuPercent`, plus the "NN psi" readout — replaces the old flat
/// `"NN psi"` text label (Dan: "a bit boring looking, add any pizzazz?").
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
    private static let glyphFrame: CGFloat = 18
    private static let glyphDrawSize: CGFloat = 16
    private static let needsDanDotSize: CGFloat = 5.5
    private static let readoutWidth: CGFloat = 60
    private static let redlineFlameSize: CGFloat = 8

    init(reading: BoilerReading, chartRoomUnseenCount: Int = 0, needsDanCount: Int = 0) {
        self.reading = reading
        self.chartRoomUnseenCount = chartRoomUnseenCount
        self.needsDanCount = needsDanCount
    }

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Image(nsImage: GaugeIcon.menubarTemplateImage())
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.glyphDrawSize, height: Self.glyphDrawSize)
                    .foregroundColor(.primary)
                if redlineActive {
                    Image(systemName: "flame.fill")
                        .font(.system(size: Self.redlineFlameSize, weight: .bold))
                        .foregroundStyle(.red)
                        .offset(x: -6, y: 5)
                }
                if needsDanCount > 0 {
                    Circle()
                        .fill(.orange)
                        .frame(width: Self.needsDanDotSize, height: Self.needsDanDotSize)
                        .offset(x: 7.25, y: -6.5)
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
    }

    private var redlineActive: Bool {
        reading.cpuPercent >= Self.redlineOnThreshold
    }
}

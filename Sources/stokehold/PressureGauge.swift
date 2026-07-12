import SwiftUI

/// A brass steam-pressure gauge: a 270° arc face with tick marks and a needle.
struct PressureGauge: View {
    let label: String
    let value: Double // 0...100
    let dangerThreshold: Double

    private let startAngle = Angle(degrees: 135)
    private let endAngle = Angle(degrees: 45 + 360)

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let radius = min(size.width, size.height) / 2 - 4

                // Bezel
                context.stroke(
                    Circle().path(in: rect.insetBy(dx: 2, dy: 2)),
                    with: .color(Color(red: 0.55, green: 0.42, blue: 0.18)),
                    lineWidth: 3
                )

                // Face
                context.fill(Circle().path(in: rect.insetBy(dx: 5, dy: 5)), with: .color(Color(red: 0.11, green: 0.09, blue: 0.06)))

                // Ticks
                for i in 0...10 {
                    let t = Double(i) / 10
                    let angle = startAngle + (endAngle - startAngle) * t
                    let inner = pointOn(center: center, radius: radius - 6, angle: angle)
                    let outer = pointOn(center: center, radius: radius - 1, angle: angle)
                    var path = Path()
                    path.move(to: inner)
                    path.addLine(to: outer)
                    let isDanger = t >= dangerThreshold / 100
                    context.stroke(path, with: .color(isDanger ? .red : Color(red: 0.85, green: 0.7, blue: 0.35)), lineWidth: 1.5)
                }

                // Needle
                let needleAngle = startAngle + (endAngle - startAngle) * (value / 100)
                let tip = pointOn(center: center, radius: radius - 8, angle: needleAngle)
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                context.stroke(needle, with: .color(.red), lineWidth: 2)

                // Hub
                context.fill(Circle().path(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(Color(red: 0.85, green: 0.7, blue: 0.35)))
            }
            .frame(width: 64, height: 64)

            Text("\(Int(value.rounded()))")
                .font(.system(.body, design: .rounded).monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func pointOn(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
    }
}

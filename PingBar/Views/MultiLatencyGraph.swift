import SwiftUI

struct LatencySeries: Identifiable {
    let id: String
    let label: String
    let samples: [LatencySample]
    let color: Color
    let warningMs: Double
    let criticalMs: Double
}

struct MultiLatencyGraph: View {
    let series: [LatencySeries]
    var height: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            let values = series.flatMap { $0.samples.compactMap(\.latencyMs) }
            guard let maxLatency = values.max(), maxLatency > 0 else { return }

            let ceiling = max(maxLatency * 1.25, 20)
            let sampleCount = max(series.map(\.samples.count).max() ?? 1, 1)

            var grid = Path()
            for fraction in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75)] {
                let y = size.height * fraction
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.14)), lineWidth: 0.5)

            for (seriesIndex, line) in series.enumerated() where line.samples.count >= 2 {
                func xPosition(index: Int) -> CGFloat {
                    let rightAlignedIndex = sampleCount - line.samples.count + index
                    return size.width * CGFloat(rightAlignedIndex) / CGFloat(max(sampleCount - 1, 1))
                }

                func point(index: Int, latency: Double) -> CGPoint {
                    let normalized = min(latency / ceiling, 1)
                    return CGPoint(
                        x: xPosition(index: index),
                        y: size.height * (1 - CGFloat(normalized))
                    )
                }

                var segment = Path()
                var hasStartedSegment = false

                for (index, sample) in line.samples.enumerated() {
                    if let latency = sample.latencyMs {
                        let p = point(index: index, latency: latency)
                        if hasStartedSegment {
                            segment.addLine(to: p)
                        } else {
                            segment.move(to: p)
                            hasStartedSegment = true
                        }
                    } else {
                        if hasStartedSegment {
                            context.stroke(segment, with: .color(line.color.opacity(0.26)), lineWidth: 0.8)
                            segment = Path()
                            hasStartedSegment = false
                        }

                        let x = xPosition(index: index)
                        let offset = CGFloat(seriesIndex % 4) * 2
                        var loss = Path()
                        loss.move(to: CGPoint(x: x, y: size.height - 10 - offset))
                        loss.addLine(to: CGPoint(x: x, y: size.height - offset))
                        context.stroke(loss, with: .color(.red.opacity(0.75)), lineWidth: 1)
                    }
                }

                if hasStartedSegment {
                    context.stroke(segment, with: .color(line.color.opacity(0.26)), lineWidth: 0.8)
                }

                for (index, sample) in line.samples.enumerated() {
                    guard let latency = sample.latencyMs else { continue }

                    let p = point(index: index, latency: latency)
                    let age = Double(line.samples.count - 1 - index)
                    let recency = max(0.32, 1 - age / 42)
                    let alert = alertColor(for: latency, in: line)
                    let radius = alert == nil
                        ? CGFloat(1.15 + recency * 0.75)
                        : CGFloat(1.35 + recency * 0.42)
                    let dot = CGRect(
                        x: p.x - radius,
                        y: p.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    if let alert {
                        let ring = dot.insetBy(dx: -0.8, dy: -0.8)
                        context.stroke(Path(ellipseIn: ring), with: .color(alert.opacity(0.34)), lineWidth: 0.55)
                        context.fill(Path(ellipseIn: dot), with: .color(alert.opacity(0.74)))
                    } else {
                        context.fill(Path(ellipseIn: dot), with: .color(line.color.opacity(0.38 + recency * 0.45)))
                    }
                }

                if let lastIndex = line.samples.lastIndex(where: { $0.latencyMs != nil }),
                   let lastLatency = line.samples[lastIndex].latencyMs {
                    let p = point(index: lastIndex, latency: lastLatency)
                    let alert = alertColor(for: lastLatency, in: line)
                    let color = alert ?? line.color
                    let haloRadius: CGFloat = alert == nil ? 3.2 : 2.7
                    let coreRadius: CGFloat = alert == nil ? 1.9 : 1.6
                    let halo = CGRect(x: p.x - haloRadius, y: p.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
                    let core = CGRect(x: p.x - coreRadius, y: p.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
                    context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.18)))
                    context.fill(Path(ellipseIn: core), with: .color(color))
                }
            }
        }
        .frame(height: height)
    }

    private func alertColor(for latency: Double, in series: LatencySeries) -> Color? {
        if latency >= series.criticalMs { return .red }
        if latency >= series.warningMs { return .yellow }
        return nil
    }
}

import SwiftUI

struct ThroughputGraph: View {
    let uploadValues: [Double]
    let downloadValues: [Double]
    var height: CGFloat = 62

    var body: some View {
        Canvas { context, size in
            let sampleCount = max(uploadValues.count, downloadValues.count)
            guard sampleCount >= 2 else { return }

            let centerY = size.height / 2
            let lanePadding: CGFloat = 4
            let upperHeight = max(centerY - lanePadding, 1)
            let lowerHeight = max(size.height - centerY - lanePadding, 1)

            drawGrid(context: context, size: size, centerY: centerY)

            drawSeries(
                values: uploadValues,
                sampleCount: sampleCount,
                context: context,
                size: size,
                baselineY: centerY,
                laneHeight: upperHeight,
                color: .blue,
                direction: -1
            )

            drawSeries(
                values: downloadValues,
                sampleCount: sampleCount,
                context: context,
                size: size,
                baselineY: centerY,
                laneHeight: lowerHeight,
                color: .green,
                direction: 1
            )
        }
        .frame(height: height)
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, centerY: CGFloat) {
        var grid = Path()
        for fraction in [CGFloat(0.25), CGFloat(0.75)] {
            let y = size.height * fraction
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.10)), lineWidth: 0.5)

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: centerY))
        baseline.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(baseline, with: .color(.secondary.opacity(0.20)), lineWidth: 0.6)
    }

    private func drawSeries(
        values: [Double],
        sampleCount: Int,
        context: GraphicsContext,
        size: CGSize,
        baselineY: CGFloat,
        laneHeight: CGFloat,
        color: Color,
        direction: CGFloat
    ) {
        guard values.count >= 2 else { return }

        let maxValue = max(values.max() ?? 0, 1)

        func xPosition(index: Int) -> CGFloat {
            let alignedIndex = sampleCount - values.count + index
            return size.width * CGFloat(alignedIndex) / CGFloat(max(sampleCount - 1, 1))
        }

        func point(index: Int) -> CGPoint {
            let normalized = min(max(values[index] / maxValue, 0), 1)
            return CGPoint(
                x: xPosition(index: index),
                y: baselineY + direction * laneHeight * CGFloat(normalized)
            )
        }

        var path = Path()
        path.move(to: point(index: 0))
        for index in 1..<values.count {
            path.addLine(to: point(index: index))
        }

        var area = path
        area.addLine(to: CGPoint(x: xPosition(index: values.count - 1), y: baselineY))
        area.addLine(to: CGPoint(x: xPosition(index: 0), y: baselineY))
        area.closeSubpath()

        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.18), color.opacity(0.03)]),
                startPoint: direction < 0 ? CGPoint(x: 0, y: 0) : CGPoint(x: 0, y: size.height),
                endPoint: CGPoint(x: 0, y: baselineY)
            )
        )
        context.stroke(path, with: .color(color.opacity(0.78)), lineWidth: 1.1)

        let lastPoint = point(index: values.count - 1)
        let halo = CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6)
        let core = CGRect(x: lastPoint.x - 1.6, y: lastPoint.y - 1.6, width: 3.2, height: 3.2)
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.16)))
        context.fill(Path(ellipseIn: core), with: .color(color))
    }
}

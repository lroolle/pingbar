import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.2
    var showArea: Bool = true
    var height: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }

            let maxVal = values.max() ?? 1
            let minVal = values.min() ?? 0
            let range = max(maxVal - minVal, 1)

            func point(at index: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let normalized = (values[index] - minVal) / range
                let y = size.height * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            var linePath = Path()
            linePath.move(to: point(at: 0))
            for i in 1..<values.count {
                linePath.addLine(to: point(at: i))
            }

            if showArea {
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                areaPath.addLine(to: CGPoint(x: 0, y: size.height))
                areaPath.closeSubpath()

                context.fill(areaPath, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.2), color.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }

            context.stroke(linePath, with: .color(color), lineWidth: lineWidth)

            let lastPoint = point(at: values.count - 1)
            let dotRect = CGRect(x: lastPoint.x - 2, y: lastPoint.y - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
        .frame(height: height)
    }
}

struct DualSparkline: View {
    let uploadValues: [Double]
    let downloadValues: [Double]
    var height: CGFloat = 30

    var body: some View {
        Canvas { context, size in
            let allValues = uploadValues + downloadValues
            guard allValues.count >= 2 else { return }

            let maxVal = max(allValues.max() ?? 1, 1)

            drawLine(context: context, size: size, values: downloadValues, maxVal: maxVal,
                     color: .green, areaOpacity: 0.12)
            drawLine(context: context, size: size, values: uploadValues, maxVal: maxVal,
                     color: .blue, areaOpacity: 0.08)
        }
        .frame(height: height)
    }

    private func drawLine(context: GraphicsContext, size: CGSize, values: [Double],
                          maxVal: Double, color: Color, areaOpacity: Double) {
        guard values.count >= 2 else { return }

        func point(at index: Int) -> CGPoint {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat(values[index] / maxVal))
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        path.move(to: point(at: 0))
        for i in 1..<values.count {
            path.addLine(to: point(at: i))
        }

        var area = path
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()

        context.fill(area, with: .color(color.opacity(areaOpacity)))
        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1)
    }
}

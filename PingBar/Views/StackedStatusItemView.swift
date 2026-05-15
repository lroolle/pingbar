import AppKit

final class StackedStatusItemView: NSView {
    private var uploadText = ""
    private var downloadText = ""
    private var health: NetworkHealth = .unknown
    private var showsHealthDot = true

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(upload: Int64, download: Int64, health: NetworkHealth, showsHealthDot: Bool) {
        let nextUploadText = Self.statusLine(prefix: "↑", bytes: upload)
        let nextDownloadText = Self.statusLine(prefix: "↓", bytes: download)

        guard nextUploadText != uploadText
                || nextDownloadText != downloadText
                || health != self.health
                || showsHealthDot != self.showsHealthDot
        else { return }

        uploadText = nextUploadText
        downloadText = nextDownloadText
        self.health = health
        self.showsHealthDot = showsHealthDot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let midY = bounds.midY
        let textX: CGFloat = showsHealthDot ? 25 : 5
        let rowHeight: CGFloat = 9
        let topY = floor(max(1, midY - rowHeight - 1))
        let bottomY = floor(min(bounds.height - rowHeight, midY))

        if showsHealthDot {
            drawPulseIcon(midY: midY)
        }

        drawLine(uploadText, at: NSPoint(x: textX, y: topY), color: .systemBlue)
        drawLine(downloadText, at: NSPoint(x: textX, y: bottomY), color: .systemGreen)
    }

    private func drawPulseIcon(midY: CGFloat) {
        let box = NSRect(x: 3, y: midY - 8, width: 16, height: 16)
        let background = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        healthColor.withAlphaComponent(0.14).setFill()
        background.fill()

        let pulse = NSBezierPath()
        pulse.lineWidth = 1.35
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        pulse.move(to: NSPoint(x: box.minX + 3, y: midY + 1))
        pulse.line(to: NSPoint(x: box.minX + 5.8, y: midY + 1))
        pulse.line(to: NSPoint(x: box.minX + 7.8, y: midY - 4.2))
        pulse.line(to: NSPoint(x: box.minX + 10, y: midY + 4.2))
        pulse.line(to: NSPoint(x: box.minX + 13, y: midY + 1))
        healthColor.setStroke()
        pulse.stroke()

        let dotRect = NSRect(x: box.maxX - 4.4, y: box.minY + 2.4, width: 3.2, height: 3.2)
        healthColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func drawLine(_ text: String, at point: NSPoint, color: NSColor) {
        let arrow = String(text.prefix(1))
        let value = String(text.dropFirst())
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

        arrow.draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
            ]
        )

        value.draw(
            at: NSPoint(x: point.x + 9, y: point.y),
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.controlTextColor,
            ]
        )
    }

    private var healthColor: NSColor {
        switch health {
        case .good:     return .systemGreen
        case .degraded: return .systemYellow
        case .poor:     return .systemRed
        case .unknown:  return .secondaryLabelColor
        }
    }

    private static func statusLine(prefix: String, bytes: Int64) -> String {
        let (value, unit) = Fmt.bytesPerSec(bytes)
        return "\(prefix) \(value)\(unit)"
    }
}

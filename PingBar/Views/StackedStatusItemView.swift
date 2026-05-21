import AppKit

struct StatusItemLine {
    let symbol: String
    let text: String
    let color: NSColor
}

enum StatusItemLayout: Equatable {
    case rows
    case columns
}

final class StackedStatusItemView: NSView {
    private var lines: [StatusItemLine] = []
    private var leadingLines: [StatusItemLine] = []
    private var trailingLines: [StatusItemLine] = []
    private var lineSignature: [String] = []
    private var health: NetworkHealth = .unknown
    private var showsHealthDot = true
    private var layout: StatusItemLayout = .rows

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(upload: Int64, download: Int64, health: NetworkHealth, showsHealthDot: Bool) {
        update(
            lines: [
                StatusItemLine(symbol: "↑", text: Self.statusLine(bytes: upload), color: .systemBlue),
                StatusItemLine(symbol: "↓", text: Self.statusLine(bytes: download), color: .systemGreen),
            ],
            health: health,
            showsHealthDot: showsHealthDot,
            layout: .rows
        )
    }

    func update(
        lines: [StatusItemLine],
        health: NetworkHealth,
        showsHealthDot: Bool,
        layout: StatusItemLayout = .rows
    ) {
        let nextLines = Array(lines.prefix(2))
        let nextSignature = nextLines.map { "\($0.symbol)|\($0.text)" }

        guard nextSignature != lineSignature
                || health != self.health
                || showsHealthDot != self.showsHealthDot
                || layout != self.layout
        else { return }

        self.lines = nextLines
        leadingLines = []
        trailingLines = []
        lineSignature = nextSignature
        self.health = health
        self.showsHealthDot = showsHealthDot
        self.layout = layout
        needsDisplay = true
    }

    func update(
        leading: [StatusItemLine],
        trailing: [StatusItemLine],
        health: NetworkHealth,
        showsHealthDot: Bool
    ) {
        let nextLeading = Array(leading.prefix(2))
        let nextTrailing = Array(trailing.prefix(2))
        let nextSignature = (nextLeading + nextTrailing).map { "\($0.symbol)|\($0.text)" }

        guard nextSignature != lineSignature
                || health != self.health
                || showsHealthDot != self.showsHealthDot
                || layout != .columns
        else { return }

        lines = []
        leadingLines = nextLeading
        trailingLines = nextTrailing
        lineSignature = nextSignature
        self.health = health
        self.showsHealthDot = showsHealthDot
        layout = .columns
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

        if layout == .columns, !leadingLines.isEmpty || !trailingLines.isEmpty {
            drawSplitRows(textX: textX, topY: topY, bottomY: bottomY)
            return
        }

        if layout == .columns, lines.count == 2 {
            drawColumns(textX: textX, midY: midY, rowHeight: rowHeight)
            return
        }

        let yPositions = lines.count <= 1 ? [floor(midY - rowHeight / 2)] : [topY, bottomY]
        for (index, line) in lines.enumerated() where index < yPositions.count {
            drawLine(line, at: NSPoint(x: textX, y: yPositions[index]), maxWidth: bounds.maxX - textX - 3)
        }
    }

    private func drawColumns(textX: CGFloat, midY: CGFloat, rowHeight: CGFloat) {
        let y = floor(midY - rowHeight / 2)
        let availableWidth = max(72, bounds.maxX - textX - 4)
        let firstWidth = min(max(46, availableWidth * 0.34), 64)
        let separatorX = textX + firstWidth + 4
        let secondX = separatorX + 7

        drawLine(lines[0], at: NSPoint(x: textX, y: y), maxWidth: firstWidth)

        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: separatorX, y: midY - 8))
        separator.line(to: NSPoint(x: separatorX, y: midY + 8))
        separator.lineWidth = 0.7
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        separator.stroke()

        drawLine(lines[1], at: NSPoint(x: secondX, y: y), maxWidth: bounds.maxX - secondX - 3)
    }

    private func drawSplitRows(textX: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        let availableWidth = max(100, bounds.maxX - textX - 4)
        let leadingWidth = min(max(52, availableWidth * 0.34), 68)
        let separatorX = textX + leadingWidth + 5
        let trailingX = separatorX + 8
        let trailingWidth = bounds.maxX - trailingX - 3
        let yPositions = [topY, bottomY]

        for (index, line) in leadingLines.enumerated() where index < yPositions.count {
            drawLine(line, at: NSPoint(x: textX, y: yPositions[index]), maxWidth: leadingWidth)
        }

        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: separatorX, y: topY - 1))
        separator.line(to: NSPoint(x: separatorX, y: bottomY + 10))
        separator.lineWidth = 0.7
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        separator.stroke()

        for (index, line) in trailingLines.enumerated() where index < yPositions.count {
            drawLine(line, at: NSPoint(x: trailingX, y: yPositions[index]), maxWidth: trailingWidth)
        }
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

    private func drawLine(_ line: StatusItemLine, at point: NSPoint, maxWidth: CGFloat) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

        line.symbol.draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: line.color,
            ]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        NSAttributedString(
            string: line.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.controlTextColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
        .draw(
            with: NSRect(x: point.x + 9, y: point.y, width: max(8, maxWidth - 9), height: 12),
            options: [.usesLineFragmentOrigin]
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

    private static func statusLine(bytes: Int64) -> String {
        let (value, unit) = Fmt.bytesPerSec(bytes)
        return "\(value)\(unit)"
    }
}

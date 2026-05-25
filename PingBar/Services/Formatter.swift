import Foundation

enum Fmt {
    static func bytesPerSec(_ bytes: Int64) -> (value: String, unit: String) {
        let abs = Double(Swift.abs(bytes))
        switch abs {
        case 0..<1024:
            return (String(format: "%.0f", abs), "B/s")
        case 1024..<(1024 * 1024):
            return (String(format: "%.1f", abs / 1024), "KB/s")
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return (String(format: "%.1f", abs / (1024 * 1024)), "MB/s")
        default:
            return (String(format: "%.2f", abs / (1024 * 1024 * 1024)), "GB/s")
        }
    }

    static func bitsPerSec(_ bits: UInt64) -> String {
        let b = Double(bits)
        switch b {
        case 0..<1000:
            return String(format: "%.0f bps", b)
        case 1000..<1_000_000:
            return String(format: "%.1f Kbps", b / 1000)
        case 1_000_000..<1_000_000_000:
            return String(format: "%.1f Mbps", b / 1_000_000)
        default:
            return String(format: "%.2f Gbps", b / 1_000_000_000)
        }
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms = ms else { return "--" }
        if ms < 1 { return "< 1 ms" }
        return String(format: "%.1f ms", ms)
    }

    static func packetLoss(_ ratio: Double) -> String {
        if ratio == 0 { return "0%" }
        return String(format: "%.1f%%", ratio * 100)
    }

    static func throughputCompact(_ bytes: Int64) -> String {
        let (val, unit) = bytesPerSec(bytes)
        return "\(val) \(unit)"
    }

    static func bytes(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        switch value {
        case 0..<1024:
            return String(format: "%.0f B", value)
        case 1024..<(1024 * 1024):
            return String(format: "%.1f KB", value / 1024)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "%.1f MB", value / (1024 * 1024))
        case (1024 * 1024 * 1024)..<(1024 * 1024 * 1024 * 1024):
            return String(format: "%.2f GB", value / (1024 * 1024 * 1024))
        default:
            return String(format: "%.2f TB", value / (1024 * 1024 * 1024 * 1024))
        }
    }
}

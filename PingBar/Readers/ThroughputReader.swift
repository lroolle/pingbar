import Foundation
import Darwin

final class ThroughputReader {
    private var previousUpload: Int64 = 0
    private var previousDownload: Int64 = 0
    private var previousReadTime: CFAbsoluteTime?
    private var previousInterface: String?
    private var hasBaseline = false

    func read(interface: String) -> ThroughputSample {
        let now = CFAbsoluteTimeGetCurrent()
        if previousInterface != interface {
            reset()
            previousInterface = interface
        }

        var sample = ThroughputSample()
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return sample }
        defer { freeifaddrs(addrs) }

        var totalUpload: Int64 = 0
        var totalDownload: Int64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard name == interface else { continue }

            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = p.pointee.ifa_data else { continue }

            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            totalUpload += Int64(ifData.ifi_obytes)
            totalDownload += Int64(ifData.ifi_ibytes)

            let baud = UInt64(ifData.ifi_baudrate)
            if baud > 0 {
                sample.linkSpeed = Double(baud) / 1_000_000.0
            }
        }

        if hasBaseline, let previousReadTime {
            let elapsed = max(now - previousReadTime, 0.001)
            if let uploadDelta = Self.counterDelta(
                current: totalUpload,
                previous: previousUpload,
                elapsed: elapsed,
                linkSpeedMbps: sample.linkSpeed
            ),
               let downloadDelta = Self.counterDelta(
                   current: totalDownload,
                   previous: previousDownload,
                   elapsed: elapsed,
                   linkSpeedMbps: sample.linkSpeed
               ) {
                sample.uploadDelta = uploadDelta
                sample.downloadDelta = downloadDelta
                sample.upload = Int64(Double(uploadDelta) / elapsed)
                sample.download = Int64(Double(downloadDelta) / elapsed)
            }
        }

        previousUpload = totalUpload
        previousDownload = totalDownload
        previousReadTime = now
        hasBaseline = true
        return sample
    }

    func reset() {
        previousUpload = 0
        previousDownload = 0
        previousReadTime = nil
        hasBaseline = false
    }

    static func counterDelta(current: Int64, previous: Int64, elapsed: CFTimeInterval, linkSpeedMbps: Double) -> Int64? {
        if current >= previous {
            let delta = current - previous
            return isPlausible(delta: delta, elapsed: elapsed, linkSpeedMbps: linkSpeedMbps) ? delta : nil
        }

        // Some macOS interface counters are effectively UInt32 and can wrap.
        // A counter reset looks similar, so only accept a wrap if the delta is plausible.
        let wrapLimit = Int64(UInt32.max) + 1
        let wrappedDelta = wrapLimit - previous + current
        if linkSpeedMbps > 0 && isPlausible(delta: wrappedDelta, elapsed: elapsed, linkSpeedMbps: linkSpeedMbps) {
            return wrappedDelta
        }

        let halfCounter = wrapLimit / 2
        return linkSpeedMbps <= 0 && previous > halfCounter && current < halfCounter ? wrappedDelta : nil
    }

    private static func isPlausible(delta: Int64, elapsed: CFTimeInterval, linkSpeedMbps: Double) -> Bool {
        guard delta >= 0 else { return false }
        guard linkSpeedMbps > 0 else { return true }

        let bytesPerSecond = linkSpeedMbps * 1_000_000 / 8
        let maxPlausibleDelta = Int64(bytesPerSecond * elapsed * 3)
        return delta <= max(maxPlausibleDelta, 16 * 1_048_576)
    }
}

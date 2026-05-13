import Foundation

final class ThroughputReader {
    private var previousUpload: Int64 = 0
    private var previousDownload: Int64 = 0
    private var hasBaseline = false

    func read(interface: String) -> ThroughputSample {
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

        if hasBaseline {
            sample.upload = wrapSafeDelta(current: totalUpload, previous: previousUpload)
            sample.download = wrapSafeDelta(current: totalDownload, previous: previousDownload)
        }

        previousUpload = totalUpload
        previousDownload = totalDownload
        hasBaseline = true
        return sample
    }

    // UInt32 counters wrap at 4GB. On gigabit that's every ~34 seconds.
    private func wrapSafeDelta(current: Int64, previous: Int64) -> Int64 {
        if current >= previous {
            return current - previous
        }
        return Int64(UInt32.max) - previous + current + 1
    }
}

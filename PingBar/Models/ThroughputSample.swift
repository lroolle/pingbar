import Foundation

struct ThroughputSample: Sendable {
    var upload: Int64 = 0
    var download: Int64 = 0
    var uploadDelta: Int64 = 0
    var downloadDelta: Int64 = 0
    var linkSpeed: Double = 0
}

struct ThroughputAggregate: Sendable {
    let sampleCount: Int
    let windowSeconds: Int
    let averageUpload: Int64
    let averageDownload: Int64
    let peakUpload: Int64
    let peakDownload: Int64
}

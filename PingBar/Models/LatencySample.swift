import Foundation

struct LatencySample {
    let date: Date
    let latencyMs: Double?

    var isLoss: Bool { latencyMs == nil }
}

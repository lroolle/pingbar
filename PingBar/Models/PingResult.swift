import Foundation

struct PingResult: Identifiable {
    let id: String
    var host: String
    var label: String
    var latencyMs: Double?
    var averageMs: Double?
    var jitterMs: Double?
    var packetLoss: Double = 0
    var isReachable: Bool = false
    var sent: Int = 0
    var received: Int = 0
    private var samples: [Double] = []
    private var outcomes: [Bool] = []
    private let maxSamples = 60

    init(id: String, host: String, label: String) {
        self.id = id
        self.host = host
        self.label = label
    }

    mutating func record(latency: Double?) {
        sent += 1
        outcomes.append(latency != nil)
        trimOutcomes()

        guard let ms = latency else {
            isReachable = false
            latencyMs = nil
            packetLoss = recentPacketLoss
            return
        }

        received += 1
        isReachable = true
        latencyMs = ms

        samples.append(ms)
        if samples.count > maxSamples {
            samples.removeFirst()
        }

        averageMs = samples.reduce(0, +) / Double(samples.count)

        if samples.count >= 2 {
            var diffs = 0.0
            for i in 1..<samples.count {
                diffs += abs(samples[i] - samples[i - 1])
            }
            jitterMs = diffs / Double(samples.count - 1)
        }

        packetLoss = recentPacketLoss
    }

    mutating func recordTimeout() {
        sent += 1
        outcomes.append(false)
        trimOutcomes()
        isReachable = false
        latencyMs = nil
        packetLoss = recentPacketLoss
    }

    private mutating func trimOutcomes() {
        if outcomes.count > maxSamples {
            outcomes.removeFirst(outcomes.count - maxSamples)
        }
    }

    private var recentPacketLoss: Double {
        guard !outcomes.isEmpty else { return 0 }
        let lost = outcomes.filter { !$0 }.count
        return Double(lost) / Double(outcomes.count)
    }
}

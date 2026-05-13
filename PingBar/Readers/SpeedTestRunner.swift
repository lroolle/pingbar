import Foundation

enum SpeedTestPreset: String, CaseIterable, Identifiable {
    case quick
    case standard
    case thorough

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick:    return "Quick (~5s)"
        case .standard: return "Standard (~20s)"
        case .thorough: return "Thorough (~60s)"
        }
    }

    var downloadSizes: [(bytes: Int, count: Int)] {
        switch self {
        case .quick:    return [(100_000, 3)]
        case .standard: return [(100_000, 3), (1_000_000, 3), (10_000_000, 2)]
        case .thorough: return [(100_000, 3), (1_000_000, 4), (10_000_000, 4), (25_000_000, 3)]
        }
    }

    var uploadSizes: [(bytes: Int, count: Int)] {
        switch self {
        case .quick:    return []
        case .standard: return [(100_000, 3), (1_000_000, 2)]
        case .thorough: return [(100_000, 3), (1_000_000, 4), (10_000_000, 2)]
        }
    }

    var latencyCount: Int {
        switch self {
        case .quick:    return 5
        case .standard: return 10
        case .thorough: return 20
        }
    }
}

struct NativeSpeedResult {
    var server: String = ""
    var clientIP: String = ""
    var location: String = ""

    var latencyMs: Double = 0
    var jitterMs: Double = 0

    var downloadBps: UInt64 = 0
    var uploadBps: UInt64 = 0

    var status: String = "ok"
    var error: String?
}

final class SpeedTestRunner {
    private static let baseURL = "https://speed.cloudflare.com"
    private var cancelled = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    func run(preset: SpeedTestPreset, noProxy: Bool) async throws -> NativeSpeedResult {
        cancelled = false
        var result = NativeSpeedResult()
        let sess = noProxy ? directSession : session

        let meta = try await fetchMeta(session: sess)
        result.clientIP = meta.clientIP
        result.server = meta.colo
        result.location = "\(meta.city), \(meta.country)"

        if cancelled { throw SpeedTestError.cancelled }

        let (latency, jitter) = try await measureLatency(count: preset.latencyCount, session: sess)
        result.latencyMs = latency
        result.jitterMs = jitter

        if cancelled { throw SpeedTestError.cancelled }

        if !preset.downloadSizes.isEmpty {
            result.downloadBps = try await measureDownload(steps: preset.downloadSizes, session: sess)
        }

        if cancelled { throw SpeedTestError.cancelled }

        if !preset.uploadSizes.isEmpty {
            result.uploadBps = try await measureUpload(steps: preset.uploadSizes, session: sess)
        }

        return result
    }

    func cancel() {
        cancelled = true
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        directSession.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    private struct MetaResponse: Codable {
        let clientIp: String
        let colo: String
        let city: String
        let country: String
    }

    private struct Meta {
        let clientIP: String
        let colo: String
        let city: String
        let country: String
    }

    private func fetchMeta(session: URLSession) async throws -> Meta {
        let url = URL(string: "\(Self.baseURL)/meta")!
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(MetaResponse.self, from: data)
        return Meta(clientIP: resp.clientIp, colo: resp.colo, city: resp.city, country: resp.country)
    }

    private func measureLatency(count: Int, session: URLSession) async throws -> (median: Double, jitter: Double) {
        var samples: [Double] = []

        for _ in 0..<count {
            if cancelled { break }
            let url = URL(string: "\(Self.baseURL)/__down?bytes=0")!
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"

            let start = CFAbsoluteTimeGetCurrent()
            let (_, _) = try await session.data(for: request)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            samples.append(elapsed)
        }

        guard !samples.isEmpty else { return (0, 0) }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]

        var jitter = 0.0
        if samples.count >= 2 {
            for i in 1..<samples.count {
                jitter += abs(samples[i] - samples[i - 1])
            }
            jitter /= Double(samples.count - 1)
        }

        return (median, jitter)
    }

    private func measureDownload(steps: [(bytes: Int, count: Int)], session: URLSession) async throws -> UInt64 {
        var allBps: [Double] = []

        for step in steps {
            for _ in 0..<step.count {
                if cancelled { break }
                let url = URL(string: "\(Self.baseURL)/__down?bytes=\(step.bytes)")!
                let start = CFAbsoluteTimeGetCurrent()
                let (data, _) = try await session.data(from: url)
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                if elapsed > 0 {
                    let bps = Double(data.count * 8) / elapsed
                    allBps.append(bps)
                }
            }
        }

        guard !allBps.isEmpty else { return 0 }

        let sorted = allBps.sorted()
        let trimCount = max(1, sorted.count / 4)
        let trimmed = Array(sorted.dropFirst(trimCount / 2).dropLast(trimCount / 2))
        let avg = trimmed.reduce(0, +) / Double(trimmed.count)

        return UInt64(avg)
    }

    private func measureUpload(steps: [(bytes: Int, count: Int)], session: URLSession) async throws -> UInt64 {
        var allBps: [Double] = []

        for step in steps {
            let payload = Data(count: step.bytes)
            for _ in 0..<step.count {
                if cancelled { break }
                let url = URL(string: "\(Self.baseURL)/__up")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = payload
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

                let start = CFAbsoluteTimeGetCurrent()
                let (_, _) = try await session.data(for: request)
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                if elapsed > 0 {
                    let bps = Double(step.bytes * 8) / elapsed
                    allBps.append(bps)
                }
            }
        }

        guard !allBps.isEmpty else { return 0 }

        let sorted = allBps.sorted()
        let trimCount = max(1, sorted.count / 4)
        let trimmed = Array(sorted.dropFirst(trimCount / 2).dropLast(trimCount / 2))
        let avg = trimmed.reduce(0, +) / Double(trimmed.count)

        return UInt64(avg)
    }
}

enum SpeedTestError: LocalizedError {
    case cancelled
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Speed test cancelled"
        case .networkError(let msg): return msg
        }
    }
}

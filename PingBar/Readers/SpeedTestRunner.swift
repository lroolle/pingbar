import Foundation
import CFNetwork

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

final class SpeedTestRunner: @unchecked Sendable {
    private static let baseURL = "https://speed.cloudflare.com"
    private let lock = NSLock()
    private var cancelled = false
    private var activeSession: URLSession?

    private static func makeSystemPathSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    private static func makeNoURLProxySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
        ]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    func run(preset: SpeedTestPreset, noProxy: Bool) async throws -> NativeSpeedResult {
        setCancelled(false)
        var result = NativeSpeedResult()
        var errors: [String] = []
        let sess = noProxy ? Self.makeNoURLProxySession() : Self.makeSystemPathSession()
        setActiveSession(sess)
        defer { setActiveSession(nil) }
        let measID = UUID().uuidString

        do {
            let meta = try await fetchMeta(session: sess)
            result.clientIP = meta.clientIP
            result.server = meta.colo
            result.location = [meta.city, meta.country].filter { !$0.isEmpty }.joined(separator: ", ")
        } catch {
            errors.append("metadata: \(error.localizedDescription)")
        }

        if isCancelled { throw SpeedTestError.cancelled }

        do {
            let (latency, jitter) = try await measureLatency(count: preset.latencyCount, measID: measID, session: sess)
            result.latencyMs = latency
            result.jitterMs = jitter
        } catch {
            errors.append("latency: \(error.localizedDescription)")
        }

        if isCancelled { throw SpeedTestError.cancelled }

        if !preset.downloadSizes.isEmpty {
            do {
                result.downloadBps = try await measureDownload(steps: preset.downloadSizes, measID: measID, session: sess)
            } catch {
                errors.append("download: \(error.localizedDescription)")
            }
        }

        if isCancelled { throw SpeedTestError.cancelled }

        if !preset.uploadSizes.isEmpty {
            do {
                result.uploadBps = try await measureUpload(steps: preset.uploadSizes, measID: measID, session: sess)
            } catch {
                errors.append("upload: \(error.localizedDescription)")
            }
        }

        if result.latencyMs == 0 && result.downloadBps == 0 && result.uploadBps == 0 {
            throw SpeedTestError.networkError(errors.joined(separator: "; "))
        }

        if !errors.isEmpty {
            result.status = "partial"
            result.error = errors.joined(separator: "; ")
        }

        return result
    }

    func cancel() {
        setCancelled(true)
        currentSession()?.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    private func setActiveSession(_ session: URLSession?) {
        lock.lock()
        activeSession = session
        lock.unlock()
    }

    private func currentSession() -> URLSession? {
        lock.lock()
        defer { lock.unlock() }
        return activeSession
    }

    private struct MetaResponse: Codable {
        let clientIp: String
        let city: String?
        let country: String?
        let colo: ColoResponse?
    }

    private struct ColoResponse: Codable {
        let iata: String?
        let city: String?
        let cca2: String?
    }

    private struct Meta {
        let clientIP: String
        let colo: String
        let city: String
        let country: String
    }

    private func fetchMeta(session: URLSession) async throws -> Meta {
        let url = try makeURL(path: "/meta")
        var request = URLRequest(url: url)
        applyCloudflareHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)

        let resp = try JSONDecoder().decode(MetaResponse.self, from: data)
        return Meta(
            clientIP: resp.clientIp,
            colo: resp.colo?.iata ?? "",
            city: resp.city ?? "",
            country: resp.country ?? ""
        )
    }

    private func measureLatency(count: Int, measID: String, session: URLSession) async throws -> (median: Double, jitter: Double) {
        var samples: [Double] = []

        for _ in 0..<count {
            if isCancelled { break }
            let url = try makeURL(path: "/__down", queryItems: [
                URLQueryItem(name: "bytes", value: "0"),
                URLQueryItem(name: "measId", value: measID),
            ])
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyCloudflareHeaders(to: &request)

            let start = CFAbsoluteTimeGetCurrent()
            let (_, response) = try await session.data(for: request)
            try validateHTTP(response)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            samples.append(elapsed)
        }

        guard !samples.isEmpty else { throw SpeedTestError.networkError("all latency probes failed") }

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

    private func measureDownload(steps: [(bytes: Int, count: Int)], measID: String, session: URLSession) async throws -> UInt64 {
        var allBps: [Double] = []

        for step in steps {
            for _ in 0..<step.count {
                if isCancelled { break }
                let url = try makeURL(path: "/__down", queryItems: [
                    URLQueryItem(name: "bytes", value: String(step.bytes)),
                    URLQueryItem(name: "measId", value: measID),
                ])
                var request = URLRequest(url: url)
                applyCloudflareHeaders(to: &request)

                let start = CFAbsoluteTimeGetCurrent()
                let (data, response) = try await session.data(for: request)
                try validateHTTP(response)
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                if elapsed > 0 {
                    let bps = Double(data.count * 8) / elapsed
                    allBps.append(bps)
                }
            }
        }

        guard !allBps.isEmpty else { throw SpeedTestError.networkError("all download measurements failed") }

        let sorted = allBps.sorted()
        let trimCount = max(1, sorted.count / 4)
        let trimmed = Array(sorted.dropFirst(trimCount / 2).dropLast(trimCount / 2))
        let avg = trimmed.reduce(0, +) / Double(trimmed.count)

        return UInt64(avg)
    }

    private func measureUpload(steps: [(bytes: Int, count: Int)], measID: String, session: URLSession) async throws -> UInt64 {
        var allBps: [Double] = []

        for step in steps {
            let payload = Data(count: step.bytes)
            for _ in 0..<step.count {
                if isCancelled { break }
                let url = try makeURL(path: "/__up", queryItems: [
                    URLQueryItem(name: "measId", value: measID),
                ])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = payload
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                applyCloudflareHeaders(to: &request)

                let start = CFAbsoluteTimeGetCurrent()
                let (_, response) = try await session.data(for: request)
                try validateHTTP(response)
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                if elapsed > 0 {
                    let bps = Double(step.bytes * 8) / elapsed
                    allBps.append(bps)
                }
            }
        }

        guard !allBps.isEmpty else { throw SpeedTestError.networkError("all upload measurements failed") }

        let sorted = allBps.sorted()
        let trimCount = max(1, sorted.count / 4)
        let trimmed = Array(sorted.dropFirst(trimCount / 2).dropLast(trimCount / 2))
        let avg = trimmed.reduce(0, +) / Double(trimmed.count)

        return UInt64(avg)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: Self.baseURL) else {
            throw SpeedTestError.networkError("invalid speed-test base URL")
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw SpeedTestError.networkError("invalid speed-test URL")
        }
        return url
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func setCancelled(_ value: Bool) {
        lock.lock()
        cancelled = value
        lock.unlock()
    }

    private func applyCloudflareHeaders(to request: inout URLRequest) {
        request.setValue(Self.baseURL + "/", forHTTPHeaderField: "Referer")
        request.setValue("PingBar/0.1", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.networkError("HTTP \(http.statusCode)")
        }
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

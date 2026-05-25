import Foundation
import CFNetwork

final class EgressTraceReader: Sendable {
    private struct CloudflareTrace {
        let fields: [String: String]

        var ip: String? { fields["ip"] }
        var colo: String? { fields["colo"] }
        var location: String? { fields["loc"] }
        var warp: String? { fields["warp"] }
        var gateway: String? { fields["gateway"] }
        var httpProtocol: String? { fields["http"] }
    }

    private static func makeDirectSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
        ]
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }

    private static func makeSystemSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }

    func read(_ targets: [EgressTraceTarget]) async -> [EgressTraceResult] {
        await withTaskGroup(of: EgressTraceResult?.self) { group in
            for target in targets where target.enabled {
                group.addTask {
                    await Self.fetch(target)
                }
            }

            var results: [EgressTraceResult] = []
            for await result in group {
                if let result { results.append(result) }
            }

            var order: [String: Int] = [:]
            for (offset, target) in targets.enumerated() where order[target.id] == nil {
                order[target.id] = offset
            }
            return results.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }
    }

    private static func fetch(_ target: EgressTraceTarget) async -> EgressTraceResult {
        guard let url = URL(string: target.url),
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return EgressTraceResult(
                target: target,
                endpoint: nil,
                durationMs: nil,
                statusCode: nil,
                error: "Invalid URL",
                date: Date()
            )
        }

        let session = target.route == .direct ? Self.makeDirectSession() : Self.makeSystemSession()
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard let statusCode, (200...299).contains(statusCode) else {
                return EgressTraceResult(
                    target: target,
                    endpoint: nil,
                    durationMs: elapsed,
                    statusCode: statusCode,
                    error: statusCode.map { "HTTP \($0)" } ?? "No HTTP response",
                    date: Date()
                )
            }

            guard let endpoint = parse(data, target: target) else {
                return EgressTraceResult(
                    target: target,
                    endpoint: nil,
                    durationMs: elapsed,
                    statusCode: statusCode,
                    error: "Trace did not include an IP",
                    date: Date()
                )
            }

            return EgressTraceResult(
                target: target,
                endpoint: endpoint,
                durationMs: elapsed,
                statusCode: statusCode,
                error: nil,
                date: Date()
            )
        } catch {
            return EgressTraceResult(
                target: target,
                endpoint: nil,
                durationMs: nil,
                statusCode: nil,
                error: error.localizedDescription,
                date: Date()
            )
        }
    }

    static func parse(_ data: Data, target: EgressTraceTarget) -> PublicEndpointInfo? {
        switch target.parser {
        case .cloudflareTrace:
            return parseCloudflareTrace(data, target: target)
        }
    }

    private static func parseCloudflareTrace(_ data: Data, target: EgressTraceTarget) -> PublicEndpointInfo? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let fields = text
            .components(separatedBy: .newlines)
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                result[key] = value
        }
        let trace = CloudflareTrace(fields: fields)
        guard let ip = trace.ip, !ip.isEmpty else { return nil }
        return PublicEndpointInfo(
            ip: ip,
            country: trace.location,
            colo: trace.colo,
            warp: trace.warp,
            gateway: trace.gateway,
            httpProtocol: trace.httpProtocol,
            traceLocation: trace.location,
            source: target.displayName
        )
    }
}

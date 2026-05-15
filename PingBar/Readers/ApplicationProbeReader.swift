import Foundation

final class ApplicationProbeReader {
    private static func makeDirectSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
        ]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }

    private static func makeSystemSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }

    func read(_ probes: [ApplicationProbe]) async -> [ApplicationProbeResult] {
        await withTaskGroup(of: ApplicationProbeResult?.self) { group in
            for probe in probes where probe.enabled {
                group.addTask { [weak self] in
                    await self?.measure(probe)
                }
            }

            var results: [ApplicationProbeResult] = []
            for await result in group {
                if let result { results.append(result) }
            }

            let order = Dictionary(uniqueKeysWithValues: probes.enumerated().map { ($0.element.id, $0.offset) })
            return results.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }
    }

    private func measure(_ probe: ApplicationProbe) async -> ApplicationProbeResult {
        guard let url = URL(string: probe.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return ApplicationProbeResult(probe: probe, durationMs: nil, statusCode: nil, error: "Invalid URL", date: Date())
        }

        let session = probe.route == .direct ? Self.makeDirectSession() : Self.makeSystemSession()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return ApplicationProbeResult(probe: probe, durationMs: elapsed, statusCode: statusCode, error: nil, date: Date())
        } catch {
            return await measureRangeGET(probe, url: url, session: session, firstError: error.localizedDescription)
        }
    }

    private func measureRangeGET(
        _ probe: ApplicationProbe,
        url: URL,
        session: URLSession,
        firstError: String
    ) async -> ApplicationProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return ApplicationProbeResult(probe: probe, durationMs: elapsed, statusCode: statusCode, error: nil, date: Date())
        } catch {
            return ApplicationProbeResult(
                probe: probe,
                durationMs: nil,
                statusCode: nil,
                error: firstError,
                date: Date()
            )
        }
    }
}

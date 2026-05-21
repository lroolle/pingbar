import Foundation
import CFNetwork

final class ApplicationProbeReader: Sendable {
    private let configureSession: @Sendable (URLSessionConfiguration) -> Void

    init(configureSession: @escaping @Sendable (URLSessionConfiguration) -> Void = { _ in }) {
        self.configureSession = configureSession
    }

    private final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var metrics: [ApplicationProbePhaseMetrics] = []

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            lock.lock()
            self.metrics.append(Self.phaseMetrics(metrics))
            lock.unlock()
        }

        func takeLatest() -> ApplicationProbePhaseMetrics? {
            lock.lock()
            defer { lock.unlock() }
            return metrics.popLast()
        }

        func clear() {
            lock.lock()
            metrics.removeAll()
            lock.unlock()
        }

        private static func phaseMetrics(_ metrics: URLSessionTaskMetrics) -> ApplicationProbePhaseMetrics {
            guard let transaction = metrics.transactionMetrics.last else {
                return ApplicationProbePhaseMetrics()
            }

            return ApplicationProbePhaseMetrics(
                dnsMs: durationMs(transaction.domainLookupStartDate, transaction.domainLookupEndDate),
                connectMs: durationMs(transaction.connectStartDate, transaction.connectEndDate),
                tlsMs: durationMs(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate),
                requestMs: durationMs(transaction.requestStartDate, transaction.requestEndDate),
                responseMs: durationMs(transaction.responseStartDate, transaction.responseEndDate),
                ttfbMs: durationMs(transaction.requestStartDate, transaction.responseStartDate),
                protocolName: transaction.networkProtocolName,
                isProxyConnection: transaction.isProxyConnection,
                isReusedConnection: transaction.isReusedConnection
            )
        }

        private static func durationMs(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end else { return nil }
            let ms = end.timeIntervalSince(start) * 1000
            return ms >= 0 ? ms : nil
        }
    }

    private static func makeDirectMeasuredSession(
        delegate: MetricsDelegate,
        configureSession: @Sendable (URLSessionConfiguration) -> Void
    ) -> URLSession {
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
        configureSession(config)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func makeSystemMeasuredSession(
        delegate: MetricsDelegate,
        configureSession: @Sendable (URLSessionConfiguration) -> Void
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        configureSession(config)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func read(_ probes: [ApplicationProbe]) async -> [ApplicationProbeResult] {
        await withTaskGroup(of: ApplicationProbeResult?.self) { group in
            let sessionConfigurator = self.configureSession
            for probe in probes where probe.enabled {
                group.addTask {
                    await Self.measure(probe, configureSession: sessionConfigurator)
                }
            }

            var results: [ApplicationProbeResult] = []
            for await result in group {
                if let result { results.append(result) }
            }

            var order: [String: Int] = [:]
            for (offset, probe) in probes.enumerated() where order[probe.id] == nil {
                order[probe.id] = offset
            }
            return results.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }
    }

    private static func measure(
        _ probe: ApplicationProbe,
        configureSession: @escaping @Sendable (URLSessionConfiguration) -> Void
    ) async -> ApplicationProbeResult {
        guard let url = URL(string: probe.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return ApplicationProbeResult(probe: probe, durationMs: nil, phaseMetrics: nil, statusCode: nil, error: "Invalid URL", date: Date())
        }

        let delegate = MetricsDelegate()
        let session = probe.route == .direct
            ? Self.makeDirectMeasuredSession(delegate: delegate, configureSession: configureSession)
            : Self.makeSystemMeasuredSession(delegate: delegate, configureSession: configureSession)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            delegate.clear()
            let (_, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard let statusCode, (200...399).contains(statusCode) else {
                return await measureRangeGET(
                    probe,
                    url: url,
                    session: session,
                    delegate: delegate,
                    firstError: statusCode.map { "HTTP \($0)" } ?? "No HTTP response"
                )
            }
            return ApplicationProbeResult(
                probe: probe,
                durationMs: elapsed,
                phaseMetrics: delegate.takeLatest(),
                statusCode: statusCode,
                error: nil,
                date: Date()
            )
        } catch {
            return await measureRangeGET(
                probe,
                url: url,
                session: session,
                delegate: delegate,
                firstError: error.localizedDescription
            )
        }
    }

    private static func measureRangeGET(
        _ probe: ApplicationProbe,
        url: URL,
        session: URLSession,
        delegate: MetricsDelegate,
        firstError: String
    ) async -> ApplicationProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            delegate.clear()
            let (_, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return ApplicationProbeResult(
                probe: probe,
                durationMs: elapsed,
                phaseMetrics: delegate.takeLatest(),
                statusCode: statusCode,
                error: firstError.isEmpty ? nil : "HEAD failed: \(firstError)",
                date: Date()
            )
        } catch {
            return ApplicationProbeResult(
                probe: probe,
                durationMs: nil,
                phaseMetrics: nil,
                statusCode: nil,
                error: firstError,
                date: Date()
            )
        }
    }
}

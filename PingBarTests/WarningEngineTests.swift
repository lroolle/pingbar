import XCTest

final class WarningEngineTests: XCTestCase {
    func testGatewayLatencyWarningBecomesCriticalAtThreshold() throws {
        var gateway = PingResult(id: "gateway", host: "192.168.1.1", label: "Gateway")
        gateway.record(latency: 80)

        let warnings = WarningEngine.evaluate(
            pingResults: ["192.168.1.1": gateway],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: "192.168.1.1"
        )

        let warning = try XCTUnwrap(warnings.first)
        XCTAssertEqual(warning.severity, .critical)
        XCTAssertEqual(warning.id, "gw-latency-critical")
    }

    func testWeakWiFiSignalProducesWarning() {
        let wifi = WiFiInfo(ssid: "Office", rssi: -75, noise: -92)

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: wifi,
            proxyStatus: ProxyStatus(),
            gateway: nil
        )

        XCTAssertTrue(warnings.contains { $0.id == "rssi-caution" })
    }

    func testWiFiRollupSuppressesInstantSignalDuplicate() throws {
        let now = Date(timeIntervalSince1970: 9_000)
        let wifi = WiFiInfo(interfaceName: "en0", ssid: "Office", rssi: -75, noise: -92)
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: wifi)
        let samples = (0..<3).compactMap { offset in
            NetworkMetricSample.wifiSignal(
                date: now.addingTimeInterval(Double(offset)),
                info: WiFiInfo(interfaceName: "en0", ssid: "Office", rssi: -75, noise: -92),
                identity: identity
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: wifi,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "wifi-radio-caution-\(identity.id)" })
        XCTAssertFalse(warnings.contains { $0.id == "rssi-caution" })
    }

    func testSystemApplicationProbeUsesProxyLatencyThresholds() throws {
        let probe = ApplicationProbe(
            id: "cloudflare-system",
            name: "Cloudflare HTTPS",
            url: "https://www.cloudflare.com/cdn-cgi/trace",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 650,
            phaseMetrics: nil,
            statusCode: 200,
            error: nil,
            date: Date()
        )

        var thresholds = WarningEngine.defaultThresholds
        thresholds.appSystemLatencyCaution = 500
        thresholds.appSystemLatencyCritical = 1_500

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [result],
            thresholds: thresholds
        )

        let warning = try XCTUnwrap(warnings.first)
        XCTAssertEqual(warning.id, "app-latency-cloudflare-system-caution")
        XCTAssertEqual(warning.severity, .caution)
    }

    func testDirectApplicationProbeUsesDirectLatencyThresholds() throws {
        let probe = ApplicationProbe(
            id: "cloudflare-direct",
            name: "Direct Cloudflare",
            url: "https://www.cloudflare.com/cdn-cgi/trace",
            route: .direct,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 320,
            phaseMetrics: nil,
            statusCode: 200,
            error: nil,
            date: Date()
        )

        var thresholds = WarningEngine.defaultThresholds
        thresholds.appDirectLatencyCaution = 250
        thresholds.appDirectLatencyCritical = 750
        thresholds.appSystemLatencyCaution = 500
        thresholds.appSystemLatencyCritical = 1_500

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [result],
            thresholds: thresholds
        )

        let warning = try XCTUnwrap(warnings.first)
        XCTAssertEqual(warning.id, "app-latency-cloudflare-direct-caution")
        XCTAssertEqual(warning.severity, .caution)
    }

    func testLatestApplicationProbeFailureProducesCautionBeforeRollupEvidence() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: nil,
            phaseMetrics: nil,
            statusCode: 503,
            error: "timed out",
            date: Date()
        )

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [result]
        )

        let warning = try XCTUnwrap(warnings.first { $0.id == "app-latency-app-system-caution" })
        XCTAssertEqual(warning.severity, .caution)
        XCTAssertTrue(warning.detail?.contains("HTTP status: 503") == true)
        XCTAssertTrue(warning.detail?.contains("Error: timed out") == true)
    }

    func testModerateApplicationLatencyIsNotCriticalWithMetricWindow() throws {
        let probe = ApplicationProbe(
            id: "cloudflare-system",
            name: "Cloudflare HTTPS",
            url: "https://www.cloudflare.com/cdn-cgi/trace",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = (0..<5).map { offset in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: 220 + Double(offset * 5),
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.severity == .critical })
        XCTAssertFalse(warnings.contains { $0.id == "app-latency-cloudflare-system-caution" })
    }

    func testApplicationLatencyCriticalRequiresSevereSustainedP95OrFailures() throws {
        let probe = ApplicationProbe(
            id: "chatgpt-system",
            name: "ChatGPT",
            url: "https://chatgpt.com/cdn-cgi/trace",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = [2_800, 3_100, 3_400, 3_800, 4_200].enumerated().map { offset, duration in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: Double(duration),
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "app-latency-chatgpt-system-critical" })
    }

    func testSingleApplicationProbeFailureInSmallWindowIsCautionNotCritical() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = [
            ApplicationProbeResult(probe: probe, durationMs: 200, phaseMetrics: nil, statusCode: 200, error: nil, date: now),
            ApplicationProbeResult(probe: probe, durationMs: nil, phaseMetrics: nil, statusCode: nil, error: "timeout", date: now.addingTimeInterval(1)),
            ApplicationProbeResult(probe: probe, durationMs: 210, phaseMetrics: nil, statusCode: 200, error: nil, date: now.addingTimeInterval(2)),
        ].map { NetworkMetricSample.applicationProbe($0, identity: nil) }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-critical" })
        XCTAssertTrue(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testApplicationLatencyCriticalIsNotHiddenByOneFailure() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = [
            ApplicationProbeResult(probe: probe, durationMs: 2_900, phaseMetrics: nil, statusCode: 200, error: nil, date: now),
            ApplicationProbeResult(probe: probe, durationMs: nil, phaseMetrics: nil, statusCode: nil, error: "timeout", date: now.addingTimeInterval(1)),
            ApplicationProbeResult(probe: probe, durationMs: 3_400, phaseMetrics: nil, statusCode: 200, error: nil, date: now.addingTimeInterval(2)),
            ApplicationProbeResult(probe: probe, durationMs: 3_800, phaseMetrics: nil, statusCode: 200, error: nil, date: now.addingTimeInterval(3)),
        ].map { NetworkMetricSample.applicationProbe($0, identity: nil) }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "app-latency-app-system-critical" })
    }

    func testGatewayRollupUsesStrictLocalLatencyCriticalThreshold() throws {
        let now = Date()
        let samples = [48, 50, 52].enumerated().map { offset, duration in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(offset)),
                host: "192.168.1.1",
                label: "Gateway",
                latencyMs: Double(duration),
                isGateway: true,
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: "192.168.1.1",
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "gw-latency-critical" })
    }

    func testRepeatedApplicationFailuresNeedCriticalRateForCriticalWarning() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = (0..<60).map { index in
            let failed = index == 10 || index == 30 || index == 50
            return NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: failed ? nil : 220,
                    phaseMetrics: nil,
                    statusCode: failed ? nil : 200,
                    error: failed ? "timeout" : nil,
                    date: now.addingTimeInterval(Double(index))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(120)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-critical" })
        XCTAssertTrue(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testRepeatedApplicationFailuresAtCriticalRateBecomeCritical() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let now = Date()
        let samples = (0..<10).map { index in
            let failed = index >= 7
            return NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: failed ? nil : 220,
                    phaseMetrics: nil,
                    statusCode: failed ? nil : 200,
                    error: failed ? "timeout" : nil,
                    date: now.addingTimeInterval(Double(index))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "app-latency-app-system-critical" })
    }

    func testExternalTwoHundredMillisecondsIsNotWarningWithMetricWindow() throws {
        let now = Date()
        let samples = [190, 200, 205, 210, 215].enumerated().map { offset, duration in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(offset)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: Double(duration),
                isGateway: false,
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-caution" })
    }

    func testSingleExternalPacketLossInHealthyWindowIsEvidenceNotWarning() throws {
        let now = Date()
        let samples = (0..<20).map { index in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(index)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: index == 5 ? nil : 80,
                isGateway: false,
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-loss-1.1.1.1-caution" })
    }

    func testExternalPacketLossAtCautionRateWarns() throws {
        let now = Date()
        let samples = (0..<20).map { index in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(index)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: index < 2 ? nil : 80,
                isGateway: false,
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertTrue(warnings.contains { $0.id == "ext-loss-1.1.1.1-caution" })
    }

    func testDefaultFallbackDoesNotWarnForTwoHundredMillisecondsExternalLatency() {
        var ping = PingResult(id: "1.1.1.1", host: "1.1.1.1", label: "Cloudflare")
        ping.record(latency: 200)

        let warnings = WarningEngine.evaluate(
            pingResults: ["1.1.1.1": ping],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-caution" })
    }

    func testDefaultFallbackSingleExternalPacketLossIsEvidenceNotWarning() {
        var ping = PingResult(id: "1.1.1.1", host: "1.1.1.1", label: "Cloudflare")
        for index in 0..<20 {
            if index == 5 {
                ping.recordTimeout()
            } else {
                ping.record(latency: 80)
            }
        }

        let warnings = WarningEngine.evaluate(
            pingResults: ["1.1.1.1": ping],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-loss-1.1.1.1-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "ext-loss-1.1.1.1-caution" })
    }

    func testDefaultFallbackRepeatedExternalPacketLossWarns() {
        var ping = PingResult(id: "1.1.1.1", host: "1.1.1.1", label: "Cloudflare")
        for index in 0..<20 {
            if index < 2 {
                ping.recordTimeout()
            } else {
                ping.record(latency: 80)
            }
        }

        let warnings = WarningEngine.evaluate(
            pingResults: ["1.1.1.1": ping],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-loss-1.1.1.1-critical" })
        XCTAssertTrue(warnings.contains { $0.id == "ext-loss-1.1.1.1-caution" })
    }

    func testDefaultFallbackDoesNotWarnForTwoHundredMillisecondsApplicationLatency() {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 200,
            phaseMetrics: nil,
            statusCode: 200,
            error: nil,
            date: Date(timeIntervalSince1970: 10_000)
        )

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [result]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testExternalRollupSuppressesLatestFallbackForSameHost() throws {
        var ping = PingResult(id: "1.1.1.1", host: "1.1.1.1", label: "Cloudflare")
        ping.record(latency: 900)
        ping.record(latency: 950)

        let now = Date()
        let samples = [180, 190, 200, 205, 210].enumerated().map { offset, duration in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(offset)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: Double(duration),
                isGateway: false,
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: ["1.1.1.1": ping],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "ext-latency-1.1.1.1-caution" })
    }

    func testApplicationRollupSuppressesLatestProbeFallbackForSameProbe() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let latest = ApplicationProbeResult(
            probe: probe,
            durationMs: 1_600,
            phaseMetrics: nil,
            statusCode: 200,
            error: nil,
            date: Date()
        )
        let now = Date()
        let samples = [260, 280, 300, 320, 340].enumerated().map { offset, duration in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: Double(duration),
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [latest],
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testApplicationRollupSuppressesLatestProbeFailureForSameProbe() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let latest = ApplicationProbeResult(
            probe: probe,
            durationMs: nil,
            phaseMetrics: nil,
            statusCode: nil,
            error: "timed out",
            date: Date()
        )
        let now = Date()
        let samples = [260, 280, 300, 320, 340].enumerated().map { offset, duration in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: Double(duration),
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [latest],
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testHealthyApplicationRollupSuppressesLatestCriticalDurationForSameProbe() throws {
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let latest = ApplicationProbeResult(
            probe: probe,
            durationMs: AppConfig.defaultAppSystemLatencyCritical + 500,
            phaseMetrics: nil,
            statusCode: 200,
            error: nil,
            date: Date()
        )
        let now = Date()
        let samples = [180, 190, 200, 210, 220].enumerated().map { offset, duration in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: Double(duration),
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: nil,
            applicationProbeResults: [latest],
            metricSummaries: [summary]
        )

        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-critical" })
        XCTAssertFalse(warnings.contains { $0.id == "app-latency-app-system-caution" })
    }

    func testDefaultICMPThresholdsComeFromAppConfig() {
        XCTAssertEqual(WarningEngine.defaultThresholds.gatewayLatencyCaution, AppConfig.defaultGatewayLatencyCaution)
        XCTAssertEqual(WarningEngine.defaultThresholds.gatewayLatencyCritical, AppConfig.defaultGatewayLatencyCritical)
        XCTAssertEqual(WarningEngine.defaultThresholds.externalLatencyCaution, AppConfig.defaultExternalLatencyCaution)
        XCTAssertEqual(WarningEngine.defaultThresholds.externalLatencyCritical, AppConfig.defaultExternalLatencyCritical)
        XCTAssertEqual(WarningEngine.defaultThresholds.packetLossCaution, AppConfig.defaultPacketLossCaution)
        XCTAssertEqual(WarningEngine.defaultThresholds.packetLossCritical, AppConfig.defaultPacketLossCritical)
    }

    func testDefaultApplicationThresholdsDoNotTreatTwoHundredMillisecondsAsWarning() {
        XCTAssertGreaterThan(WarningEngine.defaultThresholds.externalLatencyCaution, 200)
        XCTAssertGreaterThan(WarningEngine.defaultThresholds.appDirectLatencyCaution, 200)
        XCTAssertGreaterThan(WarningEngine.defaultThresholds.appSystemLatencyCaution, 200)
        XCTAssertGreaterThanOrEqual(WarningEngine.defaultThresholds.externalLatencyCritical, 800)
        XCTAssertGreaterThanOrEqual(WarningEngine.defaultThresholds.appDirectLatencyCritical, 2_000)
        XCTAssertGreaterThanOrEqual(WarningEngine.defaultThresholds.appSystemLatencyCritical, 3_000)
    }

    func testMigratesOldPersistedWarningDefaultsToNetworkExpertThresholds() throws {
        let suiteName = "WarningThresholdMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(100.0, forKey: "externalLatencyCaution")
        defaults.set(200.0, forKey: "externalLatencyCritical")
        defaults.set(250.0, forKey: "appDirectLatencyCaution")
        defaults.set(750.0, forKey: "appDirectLatencyCritical")
        defaults.set(500.0, forKey: "appSystemLatencyCaution")
        defaults.set(1_500.0, forKey: "appSystemLatencyCritical")

        let config = AppConfig(defaults: defaults)

        XCTAssertEqual(config.externalLatencyCaution, AppConfig.defaultExternalLatencyCaution)
        XCTAssertEqual(config.externalLatencyCritical, AppConfig.defaultExternalLatencyCritical)
        XCTAssertEqual(config.appDirectLatencyCaution, AppConfig.defaultAppDirectLatencyCaution)
        XCTAssertEqual(config.appDirectLatencyCritical, AppConfig.defaultAppDirectLatencyCritical)
        XCTAssertEqual(config.appSystemLatencyCaution, AppConfig.defaultAppSystemLatencyCaution)
        XCTAssertEqual(config.appSystemLatencyCritical, AppConfig.defaultAppSystemLatencyCritical)
    }

    func testWarningThresholdMigrationPreservesCustomValues() throws {
        let suiteName = "WarningThresholdMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(180.0, forKey: "externalLatencyCaution")
        defaults.set(900.0, forKey: "externalLatencyCritical")

        let config = AppConfig(defaults: defaults)

        XCTAssertEqual(config.externalLatencyCaution, 180)
        XCTAssertEqual(config.externalLatencyCritical, 900)
    }
}

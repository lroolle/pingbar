import Foundation

enum WarningEngine {
    struct Thresholds {
        var gatewayLatencyCaution: Double = AppConfig.defaultGatewayLatencyCaution
        var gatewayLatencyCritical: Double = AppConfig.defaultGatewayLatencyCritical
        var externalLatencyCaution: Double = AppConfig.defaultExternalLatencyCaution
        var externalLatencyCritical: Double = AppConfig.defaultExternalLatencyCritical
        var appDirectLatencyCaution: Double = AppConfig.defaultAppDirectLatencyCaution
        var appDirectLatencyCritical: Double = AppConfig.defaultAppDirectLatencyCritical
        var appSystemLatencyCaution: Double = AppConfig.defaultAppSystemLatencyCaution
        var appSystemLatencyCritical: Double = AppConfig.defaultAppSystemLatencyCritical
        var packetLossCaution: Double = AppConfig.defaultPacketLossCaution
        var packetLossCritical: Double = AppConfig.defaultPacketLossCritical
        var rssiCaution: Int = -70
        var rssiCritical: Int = -80
        var snrCaution: Int = 25
        var snrCritical: Int = 15

        func applicationLatencyLimits(for route: ApplicationProbeRoute) -> (caution: Double, critical: Double) {
            switch route {
            case .direct:
                return (appDirectLatencyCaution, appDirectLatencyCritical)
            case .system:
                return (appSystemLatencyCaution, appSystemLatencyCritical)
            }
        }
    }

    static let defaultThresholds = Thresholds()

    static func evaluate(
        pingResults: [String: PingResult],
        wifiInfo: WiFiInfo?,
        proxyStatus: ProxyStatus,
        gateway: String?,
        applicationProbeResults: [ApplicationProbeResult] = [],
        metricSummaries: [NetworkMetricSummary] = [],
        thresholds: Thresholds = defaultThresholds
    ) -> [Warning] {
        var warnings: [Warning] = []
        let metricWarnings = evaluateMetricSummaries(metricSummaries, thresholds: thresholds)
        let metricCoveredSources = MetricCoverage(summaries: metricSummaries)
        warnings.append(contentsOf: metricWarnings)

        if let gw = gateway, let ping = pingResults[gw] {
            let latencyCriticalID = "gw-latency-critical"
            let latencyCautionID = "gw-latency-caution"
            if let avg = ping.averageMs, !metricCoveredSources.hasGatewayLatency {
                if avg >= thresholds.gatewayLatencyCritical {
                    warnings.append(Warning(
                        id: latencyCriticalID,
                        severity: .critical,
                        title: "Gateway latency \(Fmt.latency(avg))",
                        detail: "Triggered at \(Fmt.latency(thresholds.gatewayLatencyCritical))+ average to the router. This points to local Wi-Fi, router, or LAN congestion, not a remote server."
                    ))
                } else if avg >= thresholds.gatewayLatencyCaution {
                    warnings.append(Warning(
                        id: latencyCautionID,
                        severity: .caution,
                        title: "Gateway latency \(Fmt.latency(avg))",
                        detail: "Triggered at \(Fmt.latency(thresholds.gatewayLatencyCaution))+ average to the router. Watch this before blaming DNS, proxy, or WAN transit."
                    ))
                }
            }
            let lossCriticalID = "gw-loss-critical"
            let lossCautionID = "gw-loss-caution"
            if ping.packetLoss >= thresholds.packetLossCritical && !metricCoveredSources.hasGatewayLatency {
                warnings.append(Warning(
                    id: lossCriticalID,
                    severity: .critical,
                    title: "Gateway packet loss \(Fmt.packetLoss(ping.packetLoss))",
                    detail: "Triggered at \(Fmt.packetLoss(thresholds.packetLossCritical))+ recent loss to the router. Local link is unstable before traffic leaves the LAN."
                ))
            } else if ping.packetLoss >= thresholds.packetLossCaution && !metricCoveredSources.hasGatewayLatency {
                warnings.append(Warning(
                    id: lossCautionID,
                    severity: .caution,
                    title: "Gateway packet loss \(Fmt.packetLoss(ping.packetLoss))",
                    detail: "Triggered at \(Fmt.packetLoss(thresholds.packetLossCaution))+ recent loss to the router."
                ))
            }
        }

        for (host, ping) in pingResults where host != gateway {
            let criticalID = "ext-latency-\(host)-critical"
            let cautionID = "ext-latency-\(host)-caution"
            if let avg = ping.averageMs, !metricCoveredSources.externalHosts.contains(host) {
                if avg >= thresholds.externalLatencyCritical {
                    warnings.append(Warning(
                        id: criticalID,
                        severity: .critical,
                        title: "\(ping.label) latency \(Fmt.latency(avg))",
                        detail: "Triggered at \(Fmt.latency(thresholds.externalLatencyCritical))+ average to this target. Gateway health tells whether the problem is local or upstream."
                    ))
                } else if avg >= thresholds.externalLatencyCaution {
                    warnings.append(Warning(
                        id: cautionID,
                        severity: .caution,
                        title: "\(ping.label) latency \(Fmt.latency(avg))",
                        detail: "Triggered at \(Fmt.latency(thresholds.externalLatencyCaution))+ average to this target. It can be upstream routing, target load, VPN/proxy path, or WAN congestion."
                    ))
                }
            }
            let lossCriticalID = "ext-loss-\(host)-critical"
            if hasCriticalPacketLoss(ping, threshold: thresholds.packetLossCritical) && !metricCoveredSources.externalHosts.contains(host) {
                warnings.append(Warning(
                    id: lossCriticalID,
                    severity: .critical,
                    title: "\(ping.label) packet loss \(Fmt.packetLoss(ping.packetLoss))",
                    detail: "Triggered at \(Fmt.packetLoss(thresholds.packetLossCritical))+ recent loss. Compare with gateway loss before treating it as an Internet-path issue."
                ))
            } else if hasCautionPacketLoss(ping, threshold: thresholds.packetLossCaution) && !metricCoveredSources.externalHosts.contains(host) {
                warnings.append(Warning(
                    id: "ext-loss-\(host)-caution",
                    severity: .caution,
                    title: "\(ping.label) packet loss \(Fmt.packetLoss(ping.packetLoss))",
                    detail: "Repeated recent probe loss. Compare with gateway loss before treating it as upstream routing or target trouble."
                ))
            }
        }

        for result in applicationProbeResults {
            let criticalID = "app-latency-\(result.id)-critical"
            let cautionID = "app-latency-\(result.id)-caution"
            guard !metricCoveredSources.applicationProbeIDs.contains(result.id) else { continue }
            guard result.isHealthy else {
                warnings.append(Warning(
                    id: cautionID,
                    severity: .caution,
                    title: "\(result.probe.name) probe failed",
                    detail: applicationFailureDetail(result)
                ))
                continue
            }
            guard let durationMs = result.durationMs else { continue }
            let limits = thresholds.applicationLatencyLimits(for: result.probe.route)
            if durationMs >= limits.critical {
                warnings.append(Warning(
                    id: criticalID,
                    severity: .critical,
                    title: "\(result.probe.name) \(Fmt.latency(durationMs))",
                    detail: "Triggered at \(Fmt.latency(limits.critical))+ for the \(result.probe.route.label.lowercased()) application path. This includes DNS, TCP, TLS, proxy route, server response, and URLSession overhead."
                ))
            } else if durationMs >= limits.caution {
                warnings.append(Warning(
                    id: cautionID,
                    severity: .caution,
                    title: "\(result.probe.name) \(Fmt.latency(durationMs))",
                    detail: "Triggered at \(Fmt.latency(limits.caution))+ for the \(result.probe.route.label.lowercased()) application path. Compare with ICMP RTT before blaming the network."
                ))
            }
        }

        if let wifi = wifiInfo, !metricCoveredSources.hasWiFiSignal {
            if let rssi = wifi.rssi {
                if rssi <= thresholds.rssiCritical {
                    warnings.append(Warning(
                        id: "rssi-critical",
                        severity: .critical,
                        title: "Weak Wi-Fi signal (\(rssi) dBm)",
                        detail: "Triggered at \(thresholds.rssiCritical) dBm or weaker. Low RSSI usually means distance, obstruction, antenna, or AP placement."
                    ))
                } else if rssi <= thresholds.rssiCaution {
                    warnings.append(Warning(
                        id: "rssi-caution",
                        severity: .caution,
                        title: "Wi-Fi signal \(rssi) dBm",
                        detail: "Triggered at \(thresholds.rssiCaution) dBm or weaker. This is a radio-quality warning, not proof of ISP trouble."
                    ))
                }
            }
            if let snr = wifi.snr {
                if snr <= thresholds.snrCritical {
                    warnings.append(Warning(
                        id: "snr-critical",
                        severity: .critical,
                        title: "Poor SNR (\(snr) dB)",
                        detail: "Triggered at \(thresholds.snrCritical) dB or lower. Noise is high relative to signal, so retries and latency spikes are expected."
                    ))
                } else if snr <= thresholds.snrCaution {
                    warnings.append(Warning(
                        id: "snr-caution",
                        severity: .caution,
                        title: "Low SNR (\(snr) dB)",
                        detail: "Triggered at \(thresholds.snrCaution) dB or lower. Usually interference, channel congestion, or weak signal."
                    ))
                }
            }
        }

        return deduplicated(warnings).sorted { $0.severity > $1.severity }
    }

    private struct MetricCoverage {
        let hasGatewayLatency: Bool
        let externalHosts: Set<String>
        let applicationProbeIDs: Set<String>
        let hasWiFiSignal: Bool

        init(summaries: [NetworkMetricSummary]) {
            hasGatewayLatency = summaries.contains {
                $0.kind == .gatewayLatency && $0.hasEnoughSignalForWarning
            }
            externalHosts = Set(summaries.compactMap {
                $0.kind == .externalLatency && $0.hasEnoughSignalForWarning ? $0.sourceID : nil
            })
            applicationProbeIDs = Set(summaries.compactMap {
                $0.kind == .applicationLatency && $0.hasEnoughSignalForWarning ? $0.sourceID : nil
            })
            hasWiFiSignal = summaries.contains {
                $0.kind == .wifiSignal && $0.hasEnoughSignalForWarning
            }
        }
    }

    private static func deduplicated(_ warnings: [Warning]) -> [Warning] {
        var selected: [String: Warning] = [:]
        var order: [String] = []

        for warning in warnings {
            if let existing = selected[warning.id] {
                if warning.severity > existing.severity {
                    selected[warning.id] = warning
                }
            } else {
                selected[warning.id] = warning
                order.append(warning.id)
            }
        }

        return order.compactMap { selected[$0] }
    }

    private static func applicationFailureDetail(_ result: ApplicationProbeResult) -> String {
        var parts = [
            "Latest \(result.probe.route.label.lowercased()) application probe failed."
        ]
        if let statusCode = result.statusCode {
            parts.append("HTTP status: \(statusCode).")
        }
        if let error = result.error, !error.isEmpty {
            parts.append("Error: \(error).")
        }
        parts.append("Treat this as transient until the metric rollup shows repeated failures.")
        return parts.joined(separator: " ")
    }

    private static func evaluateMetricSummaries(
        _ summaries: [NetworkMetricSummary],
        thresholds: Thresholds
    ) -> [Warning] {
        var warnings: [Warning] = []

        for summary in summaries where summary.hasEnoughSignalForWarning {
            switch summary.kind {
            case .gatewayLatency:
                evaluateGatewaySummary(summary, thresholds: thresholds, warnings: &warnings)
            case .externalLatency:
                evaluateExternalSummary(summary, thresholds: thresholds, warnings: &warnings)
            case .applicationLatency:
                evaluateApplicationSummary(summary, thresholds: thresholds, warnings: &warnings)
            case .applicationPhaseLatency:
                continue
            case .wifiSignal:
                evaluateWiFiSummary(summary, thresholds: thresholds, warnings: &warnings)
            case .throughput, .speedTestLatency, .speedTestDownload, .speedTestUpload:
                continue
            }
        }

        return warnings
    }

    private static func evaluateGatewaySummary(
        _ summary: NetworkMetricSummary,
        thresholds: Thresholds,
        warnings: inout [Warning]
    ) {
        let p95 = summary.p95 ?? summary.average
        if hasCriticalFailures(summary, rateThreshold: thresholds.packetLossCritical) {
            warnings.append(Warning(
                id: "gw-loss-critical",
                severity: .critical,
                title: "Gateway packet loss \(Fmt.packetLoss(summary.failureRate))",
                detail: "Triggered by \(summary.failureCount) failed gateway samples in the recent window. Local link or router path is unstable before traffic leaves the LAN."
            ))
        } else if hasCautionFailures(summary, rateThreshold: thresholds.packetLossCaution, singleFailureIsCaution: true) {
            warnings.append(Warning(
                id: "gw-loss-caution",
                severity: .caution,
                title: "Gateway packet loss \(Fmt.packetLoss(summary.failureRate))",
                detail: "Recent gateway probes show loss. Confirm Wi-Fi radio quality and AP load before blaming WAN transit."
            ))
        }

        guard let p95 else { return }
        if p95 >= thresholds.gatewayLatencyCritical {
            warnings.append(Warning(
                id: "gw-latency-critical",
                severity: .critical,
                title: "Gateway latency p95 \(Fmt.latency(p95))",
                detail: "Recent p95 to the router is high. This points to Wi-Fi, router, or LAN congestion, not a remote server."
            ))
        } else if p95 >= thresholds.gatewayLatencyCaution {
            warnings.append(Warning(
                id: "gw-latency-caution",
                severity: .caution,
                title: "Gateway latency p95 \(Fmt.latency(p95))",
                detail: "Recent gateway latency is elevated. Watch this before blaming DNS, proxy, or WAN transit."
            ))
        }
    }

    private static func evaluateExternalSummary(
        _ summary: NetworkMetricSummary,
        thresholds: Thresholds,
        warnings: inout [Warning]
    ) {
        let criticalFloor = max(thresholds.externalLatencyCritical, 800)
        let cautionFloor = max(thresholds.externalLatencyCaution, 250)

        if hasCriticalFailures(summary, rateThreshold: thresholds.packetLossCritical) {
            warnings.append(Warning(
                id: "ext-loss-\(summary.sourceID)-critical",
                severity: .critical,
                title: "\(summary.sourceName) packet loss \(Fmt.packetLoss(summary.failureRate))",
                detail: "Recent probes to this target are failing. Compare gateway loss to separate local Wi-Fi from upstream routing or target trouble."
            ))
        } else if hasCautionFailures(summary, rateThreshold: thresholds.packetLossCaution, singleFailureIsCaution: false) {
            warnings.append(Warning(
                id: "ext-loss-\(summary.sourceID)-caution",
                severity: .caution,
                title: "\(summary.sourceName) packet loss \(Fmt.packetLoss(summary.failureRate))",
                detail: "Recent target probes show intermittent loss. Gateway health tells whether this is local or upstream."
            ))
        }

        guard let p95 = summary.p95 ?? summary.average else { return }
        if p95 >= criticalFloor {
            warnings.append(Warning(
                id: "ext-latency-\(summary.sourceID)-critical",
                severity: .critical,
                title: "\(summary.sourceName) latency p95 \(Fmt.latency(p95))",
                detail: "Recent p95 is high enough to be user-impacting. Check gateway health, proxy/VPN path, and whether multiple targets are affected."
            ))
        } else if p95 >= cautionFloor {
            warnings.append(Warning(
                id: "ext-latency-\(summary.sourceID)-caution",
                severity: .caution,
                title: "\(summary.sourceName) latency p95 \(Fmt.latency(p95))",
                detail: "Recent p95 is elevated. This can be normal distance, upstream routing, target load, VPN/proxy path, or WAN congestion."
            ))
        }
    }

    private static func evaluateApplicationSummary(
        _ summary: NetworkMetricSummary,
        thresholds: Thresholds,
        warnings: inout [Warning]
    ) {
        let route = ApplicationProbeRoute(rawValue: summary.route ?? "") ?? .system
        let limits = thresholds.applicationLatencyLimits(for: route)
        let p95 = summary.p95 ?? summary.average
        let median = summary.median ?? summary.average

        if hasCriticalFailures(summary, rateThreshold: 0.20) {
            warnings.append(Warning(
                id: "app-latency-\(summary.sourceID)-critical",
                severity: .critical,
                title: "\(summary.sourceName) failures \(Fmt.packetLoss(summary.failureRate))",
                detail: "Recent application probes are failing often. This is likely user-impacting for this path."
            ))
            return
        }
        let hasFailureCaution = hasCautionFailures(summary, rateThreshold: 0.10, singleFailureIsCaution: true)

        guard let p95 else {
            if hasFailureCaution {
                appendApplicationFailureCaution(summary, warnings: &warnings)
            }
            return
        }
        let criticalP95 = max(limits.critical, route == .direct ? 2_000 : 3_000)
        let cautionP95 = max(limits.caution, route == .direct ? 800 : 1_000)
        let cautionMedian = max(limits.caution, route == .direct ? 650 : 800)

        if p95 >= criticalP95 {
            warnings.append(Warning(
                id: "app-latency-\(summary.sourceID)-critical",
                severity: .critical,
                title: "\(summary.sourceName) app p95 \(Fmt.latency(p95))",
                detail: "Recent application path p95 is high enough to be user-impacting. This includes DNS, TCP, TLS, proxy route, server response, and URLSession overhead."
            ))
        } else if p95 >= cautionP95 || (median ?? 0) >= cautionMedian {
            warnings.append(Warning(
                id: "app-latency-\(summary.sourceID)-caution",
                severity: .caution,
                title: "\(summary.sourceName) app p95 \(Fmt.latency(p95))",
                detail: "Recent application path is slower than expected. A single 200 ms app probe is not critical; compare with gateway and external RTT before blaming the network."
            ))
        } else if hasFailureCaution {
            appendApplicationFailureCaution(summary, warnings: &warnings)
        }
    }

    private static func evaluateWiFiSummary(
        _ summary: NetworkMetricSummary,
        thresholds: Thresholds,
        warnings: inout [Warning]
    ) {
        guard let latestRSSI = summary.latestValue else { return }
        let avgSNR = summary.secondaryAverage

        if latestRSSI <= Double(thresholds.rssiCritical) || (avgSNR ?? 100) <= Double(thresholds.snrCritical) {
            warnings.append(Warning(
                id: "wifi-radio-critical-\(summary.sourceID)",
                severity: .critical,
                title: "Wi-Fi radio weak (\(Int(round(latestRSSI))) dBm)",
                detail: "Recent radio evidence is poor. Expect retries, latency spikes, and loss before traffic reaches the gateway."
            ))
        } else if latestRSSI <= Double(thresholds.rssiCaution) || (avgSNR ?? 100) <= Double(thresholds.snrCaution) {
            warnings.append(Warning(
                id: "wifi-radio-caution-\(summary.sourceID)",
                severity: .caution,
                title: "Wi-Fi radio \(Int(round(latestRSSI))) dBm",
                detail: "Recent radio quality is marginal. Correlate with gateway p95 and packet loss before escalating to WAN or application owners."
            ))
        }
    }

    private static func hasCriticalFailures(_ summary: NetworkMetricSummary, rateThreshold: Double) -> Bool {
        summary.failureCount >= 3
            && summary.failureRate >= rateThreshold
    }

    private static func hasCriticalPacketLoss(_ ping: PingResult, threshold: Double) -> Bool {
        ping.recentLossCount >= 3
            && ping.packetLoss >= threshold
    }

    private static func hasCautionPacketLoss(_ ping: PingResult, threshold: Double) -> Bool {
        ping.recentLossCount >= 2
            && ping.recentSampleCount >= 10
            && ping.packetLoss >= threshold
    }

    private static func hasCautionFailures(
        _ summary: NetworkMetricSummary,
        rateThreshold: Double,
        singleFailureIsCaution: Bool
    ) -> Bool {
        if singleFailureIsCaution, summary.failureCount > 0 {
            return true
        }

        return summary.failureCount >= 2
            && summary.sampleCount >= 10
            && summary.failureRate >= rateThreshold
    }

    private static func appendApplicationFailureCaution(
        _ summary: NetworkMetricSummary,
        warnings: inout [Warning]
    ) {
        warnings.append(Warning(
            id: "app-latency-\(summary.sourceID)-caution",
            severity: .caution,
            title: "\(summary.sourceName) failures \(Fmt.packetLoss(summary.failureRate))",
            detail: "Recent application probes show failures. Treat this as path evidence only after comparing gateway, external RTT, and app phase timing."
        ))
    }
}

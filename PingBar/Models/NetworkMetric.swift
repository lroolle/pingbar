import Foundation

enum NetworkMetricKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case gatewayLatency
    case externalLatency
    case applicationLatency
    case applicationPhaseLatency
    case throughput
    case wifiSignal
    case speedTestLatency
    case speedTestDownload
    case speedTestUpload

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gatewayLatency:     return "Gateway latency"
        case .externalLatency:    return "External latency"
        case .applicationLatency: return "Application latency"
        case .applicationPhaseLatency: return "App phase"
        case .throughput:         return "Throughput"
        case .wifiSignal:         return "Wi-Fi signal"
        case .speedTestLatency:   return "Speed-test latency"
        case .speedTestDownload:  return "Speed-test download"
        case .speedTestUpload:    return "Speed-test upload"
        }
    }
}

enum NetworkMetricUnit: String, Codable, Sendable {
    case milliseconds
    case bytesPerSecond
    case bitsPerSecond
    case decibelMilliwatts

    var label: String {
        switch self {
        case .milliseconds:      return "ms"
        case .bytesPerSecond:    return "B/s"
        case .bitsPerSecond:     return "bps"
        case .decibelMilliwatts: return "dBm"
        }
    }
}

struct NetworkMetricSample: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let kind: NetworkMetricKind
    let sourceID: String
    let sourceName: String
    let value: Double?
    let secondaryValue: Double?
    let unit: NetworkMetricUnit
    let success: Bool
    let route: String?
    let networkID: String?
    let interfaceName: String?
    let tags: [String: String]

    init(
        id: UUID = UUID(),
        date: Date,
        kind: NetworkMetricKind,
        sourceID: String,
        sourceName: String,
        value: Double?,
        secondaryValue: Double? = nil,
        unit: NetworkMetricUnit,
        success: Bool = true,
        route: String? = nil,
        networkID: String? = nil,
        interfaceName: String? = nil,
        tags: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit
        self.success = success
        self.route = route
        self.networkID = networkID
        self.interfaceName = interfaceName
        self.tags = tags
    }

    static func latency(
        date: Date,
        host: String,
        label: String,
        latencyMs: Double?,
        isGateway: Bool,
        identity: NetworkTrafficIdentity?
    ) -> NetworkMetricSample {
        NetworkMetricSample(
            date: date,
            kind: isGateway ? .gatewayLatency : .externalLatency,
            sourceID: host,
            sourceName: label,
            value: latencyMs,
            unit: .milliseconds,
            success: latencyMs != nil,
            networkID: identity?.id,
            interfaceName: identity?.interfaceName,
            tags: ["host": host]
        )
    }

    static func applicationProbe(
        _ result: ApplicationProbeResult,
        identity: NetworkTrafficIdentity?
    ) -> NetworkMetricSample {
        var tags: [String: String] = [
            "url": result.probe.url,
            "route": result.probe.route.rawValue,
        ]
        if let statusCode = result.statusCode {
            tags["status"] = String(statusCode)
        }
        if let error = result.error, !error.isEmpty {
            tags["error"] = error
        }
        if let phases = result.phaseMetrics {
            if let dns = phases.dnsMs { tags["dnsMs"] = String(format: "%.1f", dns) }
            if let connect = phases.connectMs { tags["connectMs"] = String(format: "%.1f", connect) }
            if let tls = phases.tlsMs { tags["tlsMs"] = String(format: "%.1f", tls) }
            if let request = phases.requestMs { tags["requestMs"] = String(format: "%.1f", request) }
            if let response = phases.responseMs { tags["responseMs"] = String(format: "%.1f", response) }
            if let ttfb = phases.ttfbMs { tags["ttfbMs"] = String(format: "%.1f", ttfb) }
            if let proto = phases.protocolName, !proto.isEmpty { tags["protocol"] = proto }
            if let proxy = phases.isProxyConnection { tags["proxyConnection"] = proxy ? "true" : "false" }
            if let reused = phases.isReusedConnection { tags["reusedConnection"] = reused ? "true" : "false" }
        }

        return NetworkMetricSample(
            date: result.date,
            kind: .applicationLatency,
            sourceID: result.probe.id,
            sourceName: result.probe.name,
            value: result.durationMs,
            unit: .milliseconds,
            success: result.isHealthy,
            route: result.probe.route.rawValue,
            networkID: identity?.id,
            interfaceName: identity?.interfaceName,
            tags: tags
        )
    }

    static func applicationProbePhaseSamples(
        _ result: ApplicationProbeResult,
        identity: NetworkTrafficIdentity?
    ) -> [NetworkMetricSample] {
        guard let phases = result.phaseMetrics else { return [] }
        let values: [(id: String, label: String, value: Double?)] = [
            ("dns", "DNS", phases.dnsMs),
            ("connect", "Connect", phases.connectMs),
            ("tls", "TLS", phases.tlsMs),
            ("request", "Request", phases.requestMs),
            ("ttfb", "TTFB", phases.ttfbMs),
            ("response", "Response", phases.responseMs),
        ]

        var baseTags: [String: String] = [
            "appID": result.probe.id,
            "appName": result.probe.name,
            "url": result.probe.url,
            "route": result.probe.route.rawValue,
        ]
        if let statusCode = result.statusCode {
            baseTags["status"] = String(statusCode)
        }
        if let error = result.error, !error.isEmpty {
            baseTags["error"] = error
        }
        if let proto = phases.protocolName, !proto.isEmpty {
            baseTags["protocol"] = proto
        }
        if let proxy = phases.isProxyConnection {
            baseTags["proxyConnection"] = proxy ? "true" : "false"
        }
        if let reused = phases.isReusedConnection {
            baseTags["reusedConnection"] = reused ? "true" : "false"
        }

        return values.compactMap { phase in
            guard let value = phase.value else { return nil }
            var tags = baseTags
            tags["phase"] = phase.id
            return NetworkMetricSample(
                date: result.date,
                kind: .applicationPhaseLatency,
                sourceID: "\(result.probe.id):\(phase.id)",
                sourceName: "\(result.probe.name) \(phase.label)",
                value: value,
                unit: .milliseconds,
                success: true,
                route: result.probe.route.rawValue,
                networkID: identity?.id,
                interfaceName: identity?.interfaceName,
                tags: tags
            )
        }
    }

    static func throughput(
        date: Date,
        sample: ThroughputSample,
        identity: NetworkTrafficIdentity?
    ) -> NetworkMetricSample? {
        guard sample.upload > 0 || sample.download > 0 || sample.uploadDelta > 0 || sample.downloadDelta > 0 else {
            return nil
        }

        var tags: [String: String] = [
            "downloadDelta": String(sample.downloadDelta),
            "uploadDelta": String(sample.uploadDelta),
        ]
        if sample.linkSpeed > 0 {
            tags["linkSpeedMbps"] = String(format: "%.0f", sample.linkSpeed)
        }

        return NetworkMetricSample(
            date: date,
            kind: .throughput,
            sourceID: identity?.id ?? "interface:unknown",
            sourceName: identity?.displayName ?? "Current interface",
            value: Double(sample.download),
            secondaryValue: Double(sample.upload),
            unit: .bytesPerSecond,
            success: true,
            networkID: identity?.id,
            interfaceName: identity?.interfaceName,
            tags: tags
        )
    }

    static func wifiSignal(
        date: Date,
        info: WiFiInfo,
        identity: NetworkTrafficIdentity?
    ) -> NetworkMetricSample? {
        guard let rssi = info.rssi else { return nil }

        var tags: [String: String] = [:]
        if let ssid = info.ssid { tags["ssid"] = ssid }
        if let bssid = info.bssid { tags["bssid"] = bssid }
        if let channel = info.channel { tags["channel"] = String(channel) }
        if let band = info.channelBand { tags["band"] = band }
        if let width = info.channelWidth { tags["width"] = width }
        if let txRate = info.transmitRate { tags["txRateMbps"] = String(format: "%.0f", txRate) }
        if let noise = info.noise { tags["noise"] = String(noise) }

        return NetworkMetricSample(
            date: date,
            kind: .wifiSignal,
            sourceID: identity?.id ?? info.interfaceName ?? "wifi",
            sourceName: info.ssid ?? identity?.displayName ?? "Wi-Fi",
            value: Double(rssi),
            secondaryValue: info.snr.map(Double.init),
            unit: .decibelMilliwatts,
            success: true,
            networkID: identity?.id,
            interfaceName: identity?.interfaceName ?? info.interfaceName,
            tags: tags
        )
    }

    static func speedTest(
        date: Date,
        kind: NetworkMetricKind,
        value: Double,
        server: String,
        location: String,
        status: String,
        identity: NetworkTrafficIdentity?,
        noProxy: Bool
    ) -> NetworkMetricSample {
        let unit: NetworkMetricUnit = kind == .speedTestLatency ? .milliseconds : .bitsPerSecond
        return NetworkMetricSample(
            date: date,
            kind: kind,
            sourceID: noProxy ? "speedtest:no-proxy" : "speedtest:system",
            sourceName: noProxy ? "Speed test no proxy" : "Speed test system",
            value: value,
            unit: unit,
            success: status != "error",
            route: noProxy ? "direct" : "system",
            networkID: identity?.id,
            interfaceName: identity?.interfaceName,
            tags: [
                "server": server,
                "location": location,
                "status": status,
            ]
        )
    }
}

struct NetworkMetricSummary: Identifiable, Equatable, Sendable {
    let kind: NetworkMetricKind
    let sourceID: String
    let sourceName: String
    let unit: NetworkMetricUnit
    let route: String?
    let networkID: String?
    let interfaceName: String?
    let windowStart: Date
    let windowEnd: Date
    let sampleCount: Int
    let successCount: Int
    let failureCount: Int
    let min: Double?
    let average: Double?
    let median: Double?
    let p95: Double?
    let max: Double?
    let jitter: Double?
    let latestValue: Double?
    let latestDate: Date?
    let secondaryAverage: Double?
    let secondaryLatest: Double?

    var id: String {
        [
            kind.rawValue,
            sourceID,
            route ?? "",
            networkID ?? "",
            String(Int(windowStart.timeIntervalSince1970)),
            String(Int(windowEnd.timeIntervalSince1970)),
        ].joined(separator: "|")
    }

    var failureRate: Double {
        guard sampleCount > 0 else { return 0 }
        return Double(failureCount) / Double(sampleCount)
    }

    var hasEnoughSignalForWarning: Bool {
        sampleCount >= 3 || failureCount >= 2
    }

    static func make(
        samples: [NetworkMetricSample],
        windowStart: Date,
        windowEnd: Date
    ) -> NetworkMetricSummary? {
        guard let first = samples.first else { return nil }
        let sortedByDate = samples.sorted { $0.date < $1.date }
        let averageWeightedPairs = sortedByDate.compactMap { sample -> WeightedValue? in
            guard let value = sample.value else { return nil }
            return WeightedValue(value: value, count: sample.coalescedValueCount)
        }
        let medianValues = sortedByDate.compactMap { sample -> WeightedValue? in
            guard let value = sample.coalescedMedianValue ?? sample.value else { return nil }
            return WeightedValue(value: value, count: sample.coalescedValueCount)
        }
        let p95Values = sortedByDate.compactMap { sample -> WeightedValue? in
            guard let value = sample.coalescedP95Value ?? sample.value else { return nil }
            return WeightedValue(value: value, count: sample.coalescedValueCount)
        }
        let minValues = sortedByDate.compactMap { $0.coalescedMinValue ?? $0.value }.sorted()
        let maxValues = sortedByDate.compactMap { $0.coalescedMaxValue ?? $0.value }.sorted()
        let secondaryValues = sortedByDate.compactMap { sample -> WeightedValue? in
            guard let secondaryValue = sample.secondaryValue else { return nil }
            return WeightedValue(value: secondaryValue, count: sample.coalescedValueCount)
        }
        let successCount = sortedByDate.reduce(0) { $0 + $1.coalescedOutcomeCounts.successes }
        let failureCount = sortedByDate.reduce(0) { $0 + $1.coalescedOutcomeCounts.failures }
        let latest = sortedByDate.last

        return NetworkMetricSummary(
            kind: first.kind,
            sourceID: first.sourceID,
            sourceName: latest?.sourceName ?? first.sourceName,
            unit: first.unit,
            route: first.route,
            networkID: latest?.networkID ?? first.networkID,
            interfaceName: latest?.interfaceName ?? first.interfaceName,
            windowStart: windowStart,
            windowEnd: windowEnd,
            sampleCount: successCount + failureCount,
            successCount: successCount,
            failureCount: failureCount,
            min: minValues.first,
            average: weightedAverage(averageWeightedPairs),
            median: weightedPercentile(medianValues, 0.50),
            p95: weightedPercentile(p95Values, 0.95),
            max: maxValues.last,
            jitter: weightedJitter(sortedByDate),
            latestValue: latest?.value,
            latestDate: latest?.date,
            secondaryAverage: weightedAverage(secondaryValues),
            secondaryLatest: latest?.secondaryValue
        )
    }

    private struct WeightedValue {
        let value: Double
        let count: Int
    }

    private static func weightedAverage(_ values: [WeightedValue]) -> Double? {
        let totalCount = values.reduce(0) { $0 + Swift.max(0, $1.count) }
        guard totalCount > 0 else { return nil }
        let total = values.reduce(0.0) { $0 + $1.value * Double(Swift.max(0, $1.count)) }
        return total / Double(totalCount)
    }

    private static func weightedPercentile(_ values: [WeightedValue], _ p: Double) -> Double? {
        let sortedValues = values
            .filter { $0.count > 0 }
            .sorted { $0.value < $1.value }
        let totalCount = sortedValues.reduce(0) { $0 + $1.count }
        guard totalCount > 0 else { return nil }
        guard totalCount > 1 else { return sortedValues[0].value }

        let clamped = Swift.min(Swift.max(p, 0), 1)
        let position = Double(totalCount - 1) * clamped
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        let lowerValue = weightedValue(at: lower, in: sortedValues)
        if lower == upper { return lowerValue }

        let weight = position - Double(lower)
        let upperValue = weightedValue(at: upper, in: sortedValues)
        return lowerValue + (upperValue - lowerValue) * weight
    }

    private static func weightedValue(at index: Int, in sortedValues: [WeightedValue]) -> Double {
        var seen = 0
        for pair in sortedValues {
            let next = seen + pair.count
            if index < next { return pair.value }
            seen = next
        }
        return sortedValues.last?.value ?? 0
    }

    private static func weightedJitter(_ sortedByDate: [NetworkMetricSample]) -> Double? {
        var weightedTotal = 0.0
        var weight = 0
        var previousValue: Double?

        for sample in sortedByDate where sample.unit == .milliseconds {
            if let internalJitter = sample.coalescedJitterValue {
                let internalWeight = Swift.max(0, sample.coalescedValueCount - 1)
                weightedTotal += internalJitter * Double(internalWeight)
                weight += internalWeight
            }

            guard let value = sample.value else { continue }
            if let previousValue {
                weightedTotal += abs(value - previousValue)
                weight += 1
            }
            previousValue = value
        }

        guard weight > 0 else { return nil }
        return weightedTotal / Double(weight)
    }
}

struct NetworkMetricStoreSnapshot: Equatable, Sendable {
    let samples: [NetworkMetricSample]
    let summaries: [NetworkMetricSummary]
}

private extension NetworkMetricSample {
    static let maxCoalescedCount = 1_000

    var isCoalescedSample: Bool {
        tags["coalesced"] == "true"
    }

    var coalescedSampleCount: Int {
        guard isCoalescedSample else { return 1 }
        return Self.clampedCoalescedCount(tags["samples"].flatMap(Int.init), minimum: 1)
    }

    var coalescedValueCount: Int {
        guard isCoalescedSample else { return 1 }
        if let valueCount = tags["valueSamples"].flatMap(Int.init) {
            return Swift.min(Self.clampedCoalescedCount(valueCount, minimum: 0), coalescedSampleCount)
        }
        return coalescedSampleCount
    }

    var coalescedOutcomeCounts: (successes: Int, failures: Int) {
        guard isCoalescedSample else {
            return success ? (1, 0) : (0, 1)
        }

        let sampleCount = coalescedSampleCount
        let successes = Self.clampedCoalescedCount(tags["successes"].flatMap(Int.init), minimum: 0)
        let failures = Self.clampedCoalescedCount(tags["failures"].flatMap(Int.init), minimum: 0)
        guard successes + failures == sampleCount else {
            return success ? (sampleCount, 0) : (0, sampleCount)
        }
        return (successes, failures)
    }

    var coalescedMinValue: Double? {
        guard isCoalescedSample else { return nil }
        return tags["min"].flatMap(Double.init)
    }

    var coalescedMedianValue: Double? {
        guard isCoalescedSample else { return nil }
        return tags["median"].flatMap(Double.init)
    }

    var coalescedP95Value: Double? {
        guard isCoalescedSample else { return nil }
        return tags["p95"].flatMap(Double.init)
    }

    var coalescedMaxValue: Double? {
        guard isCoalescedSample else { return nil }
        return tags["max"].flatMap(Double.init)
    }

    var coalescedJitterValue: Double? {
        guard isCoalescedSample else { return nil }
        return tags["jitter"].flatMap(Double.init)
    }

    private static func clampedCoalescedCount(_ value: Int?, minimum: Int) -> Int {
        Swift.min(Swift.max(value ?? minimum, minimum), maxCoalescedCount)
    }
}

enum NetworkMetricFilters {
    static func currentNetworkSummaries(
        _ summaries: [NetworkMetricSummary],
        currentNetworkID: String?
    ) -> [NetworkMetricSummary] {
        guard let currentNetworkID else { return summaries }
        return summaries.filter { summary in
            guard let networkID = summary.networkID else { return true }
            return networkID == currentNetworkID
        }
    }
}

enum NetworkMetricDiagnostics {
    static let applicationPhaseKeys = ["dnsMs", "connectMs", "tlsMs", "ttfbMs", "responseMs"]

    static func latestTagValue(
        samples: [NetworkMetricSample],
        summary: NetworkMetricSummary,
        key: String
    ) -> String? {
        samples
            .filter {
                $0.kind == summary.kind
                    && $0.sourceID == summary.sourceID
                    && $0.route == summary.route
                    && $0.networkID == summary.networkID
                    && $0.tags[key] != nil
            }
            .max { $0.date < $1.date }?
            .tags[key]
    }

    static func applicationPhaseLabels(
        samples: [NetworkMetricSample],
        summary: NetworkMetricSummary
    ) -> [String] {
        applicationPhaseKeys.compactMap { key in
            guard let value = latestTagValue(samples: samples, summary: summary, key: key) else {
                return nil
            }
            return "\(key.replacingOccurrences(of: "Ms", with: ""))=\(value)ms"
        }
    }

    static func formattedValue(_ value: Double, unit: NetworkMetricUnit) -> String {
        switch unit {
        case .milliseconds:
            return Fmt.latency(value)
        case .bytesPerSecond:
            return Fmt.throughputCompact(Int64(value))
        case .bitsPerSecond:
            return Fmt.bitsPerSec(UInt64(Swift.max(0, value)))
        case .decibelMilliwatts:
            return "\(Int(round(value))) dBm"
        }
    }

    static func compactRollupLine(_ summary: NetworkMetricSummary) -> String {
        var parts = [
            "\(summary.kind.label): \(summary.sourceName)",
            "n=\(summary.sampleCount)",
        ]
        if summary.failureCount > 0 {
            parts.append("fail=\(Fmt.packetLoss(summary.failureRate))")
        }
        if let median = summary.median {
            parts.append("p50=\(formattedValue(median, unit: summary.unit))")
        }
        if let p95 = summary.p95 {
            parts.append("p95=\(formattedValue(p95, unit: summary.unit))")
        } else if let latest = summary.latestValue {
            parts.append("latest=\(formattedValue(latest, unit: summary.unit))")
        }
        if let jitter = summary.jitter, summary.unit == .milliseconds {
            parts.append("jit=\(formattedValue(jitter, unit: summary.unit))")
        }
        if let secondary = summary.secondaryAverage {
            let label = summary.kind == .throughput ? "upAvg" : "secondary"
            parts.append("\(label)=\(formattedValue(secondary, unit: summary.unit))")
        }
        return parts.joined(separator: "  ")
    }

    static func rollupSeverityBand(
        for summary: NetworkMetricSummary,
        policy: NetworkMetricSeverityPolicy = .defaults
    ) -> NetworkMetricSeverityBand {
        if hasCriticalFailures(summary, policy: policy) {
            return .critical
        }

        let failureBand = failureSeverityBand(summary, policy: policy)

        switch summary.kind {
        case .gatewayLatency:
            guard let p95 = summary.p95 else { return failureBand ?? .neutral }
            if p95 >= policy.gatewayLatencyCritical { return .critical }
            if p95 >= policy.gatewayLatencyCaution { return .caution }
            return failureBand ?? .good

        case .externalLatency:
            guard let p95 = summary.p95 else { return failureBand ?? .neutral }
            if p95 >= Swift.max(policy.externalLatencyCritical, 800) { return .critical }
            if p95 >= Swift.max(policy.externalLatencyCaution, 250) { return .caution }
            return failureBand ?? .good

        case .applicationLatency:
            guard let p95 = summary.p95 else { return failureBand ?? .neutral }
            let route = ApplicationProbeRoute(rawValue: summary.route ?? "") ?? .system
            let limits = policy.applicationLatencyLimits(for: route)
            let critical = Swift.max(limits.critical, route == .direct ? 2_000 : 3_000)
            let caution = Swift.max(limits.caution, route == .direct ? 800 : 1_000)
            if p95 >= critical { return .critical }
            if p95 >= caution { return .caution }
            return failureBand ?? .good

        case .applicationPhaseLatency:
            guard let p95 = summary.p95 else { return failureBand ?? .neutral }
            let thresholds = applicationPhaseThresholds(for: summary)
            if p95 >= thresholds.critical { return .critical }
            if p95 >= thresholds.caution { return .caution }
            return failureBand ?? .good

        case .wifiSignal:
            guard let rssi = summary.latestValue else { return failureBand ?? .neutral }
            if rssi <= Double(policy.rssiCritical) { return .critical }
            if rssi <= Double(policy.rssiCaution) { return .caution }
            return failureBand ?? .good

        case .throughput, .speedTestLatency, .speedTestDownload, .speedTestUpload:
            return failureBand ?? .neutral
        }
    }

    private static func hasCriticalFailures(
        _ summary: NetworkMetricSummary,
        policy: NetworkMetricSeverityPolicy
    ) -> Bool {
        let rateThreshold: Double
        switch summary.kind {
        case .gatewayLatency, .externalLatency:
            rateThreshold = policy.packetLossCritical
        case .applicationLatency, .applicationPhaseLatency:
            rateThreshold = policy.applicationFailureRateCritical
        case .throughput, .wifiSignal, .speedTestLatency, .speedTestDownload, .speedTestUpload:
            rateThreshold = policy.failureRateCritical
        }

        return summary.failureCount >= 3
            && summary.failureRate >= rateThreshold
    }

    private static func failureSeverityBand(
        _ summary: NetworkMetricSummary,
        policy: NetworkMetricSeverityPolicy
    ) -> NetworkMetricSeverityBand? {
        guard summary.failureCount > 0 else { return nil }

        switch summary.kind {
        case .gatewayLatency:
            return .caution
        case .externalLatency:
            guard summary.failureCount >= 2,
                  summary.sampleCount >= 10,
                  summary.failureRate >= policy.packetLossCaution
            else { return nil }
            return .caution
        case .applicationLatency, .applicationPhaseLatency:
            return .caution
        case .throughput, .wifiSignal, .speedTestLatency, .speedTestDownload, .speedTestUpload:
            return .caution
        }
    }

    private static func applicationPhaseThresholds(for summary: NetworkMetricSummary) -> (caution: Double, critical: Double) {
        let phase = summary.sourceID.split(separator: ":").last.map(String.init) ?? ""
        switch phase {
        case "dns":
            return (100, 500)
        case "connect":
            return (250, 1_000)
        case "tls":
            return (500, 1_500)
        case "request":
            return (100, 500)
        case "response":
            return (500, 2_000)
        case "ttfb":
            return (1_000, 3_000)
        default:
            return (1_000, 3_000)
        }
    }
}

struct NetworkMetricSeverityPolicy: Equatable, Sendable {
    var gatewayLatencyCaution: Double
    var gatewayLatencyCritical: Double
    var externalLatencyCaution: Double
    var externalLatencyCritical: Double
    var appDirectLatencyCaution: Double
    var appDirectLatencyCritical: Double
    var appSystemLatencyCaution: Double
    var appSystemLatencyCritical: Double
    var packetLossCaution: Double
    var packetLossCritical: Double
    var applicationFailureRateCritical: Double
    var failureRateCritical: Double
    var rssiCaution: Int
    var rssiCritical: Int

    static let defaults = NetworkMetricSeverityPolicy(
        gatewayLatencyCaution: AppConfig.defaultGatewayLatencyCaution,
        gatewayLatencyCritical: AppConfig.defaultGatewayLatencyCritical,
        externalLatencyCaution: AppConfig.defaultExternalLatencyCaution,
        externalLatencyCritical: AppConfig.defaultExternalLatencyCritical,
        appDirectLatencyCaution: AppConfig.defaultAppDirectLatencyCaution,
        appDirectLatencyCritical: AppConfig.defaultAppDirectLatencyCritical,
        appSystemLatencyCaution: AppConfig.defaultAppSystemLatencyCaution,
        appSystemLatencyCritical: AppConfig.defaultAppSystemLatencyCritical,
        packetLossCaution: AppConfig.defaultPacketLossCaution,
        packetLossCritical: AppConfig.defaultPacketLossCritical,
        applicationFailureRateCritical: 0.20,
        failureRateCritical: 0.20,
        rssiCaution: -70,
        rssiCritical: -80
    )

    init(
        gatewayLatencyCaution: Double,
        gatewayLatencyCritical: Double,
        externalLatencyCaution: Double,
        externalLatencyCritical: Double,
        appDirectLatencyCaution: Double,
        appDirectLatencyCritical: Double,
        appSystemLatencyCaution: Double,
        appSystemLatencyCritical: Double,
        packetLossCaution: Double = AppConfig.defaultPacketLossCaution,
        packetLossCritical: Double = AppConfig.defaultPacketLossCritical,
        applicationFailureRateCritical: Double = 0.20,
        failureRateCritical: Double,
        rssiCaution: Int,
        rssiCritical: Int
    ) {
        self.gatewayLatencyCaution = gatewayLatencyCaution
        self.gatewayLatencyCritical = gatewayLatencyCritical
        self.externalLatencyCaution = externalLatencyCaution
        self.externalLatencyCritical = externalLatencyCritical
        self.appDirectLatencyCaution = appDirectLatencyCaution
        self.appDirectLatencyCritical = appDirectLatencyCritical
        self.appSystemLatencyCaution = appSystemLatencyCaution
        self.appSystemLatencyCritical = appSystemLatencyCritical
        self.packetLossCaution = packetLossCaution
        self.packetLossCritical = packetLossCritical
        self.applicationFailureRateCritical = applicationFailureRateCritical
        self.failureRateCritical = failureRateCritical
        self.rssiCaution = rssiCaution
        self.rssiCritical = rssiCritical
    }

    init(config: AppConfig) {
        self.init(
            gatewayLatencyCaution: config.gatewayLatencyCaution,
            gatewayLatencyCritical: config.gatewayLatencyCritical,
            externalLatencyCaution: config.externalLatencyCaution,
            externalLatencyCritical: config.externalLatencyCritical,
            appDirectLatencyCaution: config.appDirectLatencyCaution,
            appDirectLatencyCritical: config.appDirectLatencyCritical,
            appSystemLatencyCaution: config.appSystemLatencyCaution,
            appSystemLatencyCritical: config.appSystemLatencyCritical,
            packetLossCaution: config.packetLossCaution,
            packetLossCritical: config.packetLossCritical,
            applicationFailureRateCritical: 0.20,
            failureRateCritical: 0.20,
            rssiCaution: -70,
            rssiCritical: -80
        )
    }

    func applicationLatencyLimits(for route: ApplicationProbeRoute) -> (caution: Double, critical: Double) {
        switch route {
        case .direct:
            return (appDirectLatencyCaution, appDirectLatencyCritical)
        case .system:
            return (appSystemLatencyCaution, appSystemLatencyCritical)
        }
    }
}

enum NetworkMetricSeverityBand: Equatable, Sendable {
    case good
    case caution
    case critical
    case neutral
}

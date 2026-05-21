import Foundation

final class NetworkMetricStore {
    private let fileURL: URL
    private let retention: TimeInterval
    private let rawRetention: TimeInterval
    private let coalescingInterval: TimeInterval
    private let maxSamples: Int
    private let saveInterval: TimeInterval
    private var samples: [NetworkMetricSample]
    private var lastSave = Date.distantPast

    init(
        fileURL: URL? = nil,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        rawRetention: TimeInterval = 2 * 60 * 60,
        coalescingInterval: TimeInterval = 5 * 60,
        maxSamples: Int = 20_000,
        saveInterval: TimeInterval = 30,
        now: Date = Date()
    ) {
        self.fileURL = fileURL ?? Self.defaultStoreURL()
        self.retention = retention
        self.rawRetention = min(max(60, rawRetention), retention)
        self.coalescingInterval = max(60, coalescingInterval)
        self.maxSamples = max(1, maxSamples)
        self.saveInterval = max(1, saveInterval)
        let loadedSamples = Self.loadSamples(from: self.fileURL)
        samples = loadedSamples
        prune(referenceDate: now)
        if samples != loadedSamples {
            save(now: now)
        }
    }

    var currentSnapshot: NetworkMetricStoreSnapshot {
        snapshot(window: 15 * 60)
    }

    @discardableResult
    func record(_ sample: NetworkMetricSample, now: Date = Date()) -> NetworkMetricStoreSnapshot {
        record([sample], now: now)
    }

    @discardableResult
    func record(_ newSamples: [NetworkMetricSample], now: Date = Date()) -> NetworkMetricStoreSnapshot {
        guard !newSamples.isEmpty else { return snapshot(window: 15 * 60, endingAt: now) }

        samples.append(contentsOf: newSamples)
        prune(referenceDate: now)

        if now.timeIntervalSince(lastSave) >= saveInterval || newSamples.count >= 10 {
            save(now: now)
        }

        return snapshot(window: 15 * 60, endingAt: now)
    }

    func snapshot(window: TimeInterval, endingAt end: Date = Date()) -> NetworkMetricStoreSnapshot {
        let start = end.addingTimeInterval(-window)
        let windowSamples = samples.filter { $0.date >= start && $0.date <= end }
        return NetworkMetricStoreSnapshot(
            samples: windowSamples.sorted { $0.date < $1.date },
            summaries: summaries(for: windowSamples, windowStart: start, windowEnd: end)
        )
    }

    func summaries(
        kinds: Set<NetworkMetricKind>? = nil,
        window: TimeInterval,
        endingAt end: Date = Date()
    ) -> [NetworkMetricSummary] {
        let start = end.addingTimeInterval(-window)
        let filtered = samples.filter { sample in
            sample.date >= start && sample.date <= end && (kinds?.contains(sample.kind) ?? true)
        }
        return summaries(for: filtered, windowStart: start, windowEnd: end)
    }

    func bucketedSummaries(
        kind: NetworkMetricKind,
        interval: TimeInterval,
        window: TimeInterval,
        endingAt end: Date = Date()
    ) -> [NetworkMetricSummary] {
        let interval = max(1, interval)
        let start = end.addingTimeInterval(-window)
        let filtered = samples.filter { $0.kind == kind && $0.date >= start && $0.date <= end }
        let groups = Dictionary(grouping: filtered) { sample in
            Int(floor(sample.date.timeIntervalSince(start) / interval))
        }

        return groups.map { offset, bucketSamples in
            let bucketStart = start.addingTimeInterval(Double(offset) * interval)
            let bucketEnd = min(bucketStart.addingTimeInterval(interval), end)
            return summaries(for: bucketSamples, windowStart: bucketStart, windowEnd: bucketEnd)
        }
        .flatMap { $0 }
        .sorted {
            if $0.windowStart == $1.windowStart {
                return $0.sourceName < $1.sourceName
            }
            return $0.windowStart < $1.windowStart
        }
    }

    @discardableResult
    func reset(now: Date = Date()) -> NetworkMetricStoreSnapshot {
        samples = []
        try? FileManager.default.removeItem(at: fileURL)
        lastSave = Date.distantPast
        return snapshot(window: 15 * 60, endingAt: now)
    }

    func flush() {
        save()
    }

    private func prune(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-retention)
        samples = samples.filter { $0.date >= cutoff }
        coalesceSamplesOlderThan(referenceDate.addingTimeInterval(-rawRetention))
        if samples.count > maxSamples {
            enforceSampleCap()
        }
        samples.sort { $0.date < $1.date }
    }

    private func enforceSampleCap() {
        let durableSamples = samples.filter { sample in
            sample.tags["coalesced"] == "true" || !sample.kind.isCoalescible
        }
        let rawSamples = samples.filter { sample in
            sample.tags["coalesced"] != "true" && sample.kind.isCoalescible
        }

        if durableSamples.count >= maxSamples {
            samples = Array(durableSamples.sorted { $0.date > $1.date }.prefix(maxSamples))
            return
        }

        let rawBudget = maxSamples - durableSamples.count
        samples = durableSamples + Array(rawSamples.sorted { $0.date > $1.date }.prefix(rawBudget))
    }

    private func coalesceSamplesOlderThan(_ cutoff: Date) {
        guard coalescingInterval > 0 else { return }

        var retained: [NetworkMetricSample] = []
        var coalescingCandidates: [NetworkMetricCoalescingKey: [NetworkMetricSample]] = [:]

        for sample in samples {
            guard sample.date < cutoff,
                  sample.kind.isCoalescible,
                  sample.tags["coalesced"] != "true"
            else {
                retained.append(sample)
                continue
            }

            let bucketStart = floor(sample.date.timeIntervalSince1970 / coalescingInterval) * coalescingInterval
            let key = NetworkMetricCoalescingKey(
                kind: sample.kind,
                sourceID: sample.sourceID,
                route: sample.route,
                networkID: sample.networkID,
                unit: sample.unit,
                bucketStart: bucketStart
            )
            coalescingCandidates[key, default: []].append(sample)
        }

        samples = retained + coalescingCandidates.compactMap { key, bucketSamples in
            coalescedSample(for: key, samples: bucketSamples)
        }
    }

    private func coalescedSample(
        for key: NetworkMetricCoalescingKey,
        samples: [NetworkMetricSample]
    ) -> NetworkMetricSample? {
        guard let first = samples.min(by: { $0.date < $1.date }) else { return nil }
        let summary = NetworkMetricSummary.make(
            samples: samples,
            windowStart: Date(timeIntervalSince1970: key.bucketStart),
            windowEnd: Date(timeIntervalSince1970: key.bucketStart + coalescingInterval)
        )
        let latest = samples.max { $0.date < $1.date } ?? first
        var tags: [String: String] = [
            "coalesced": "true",
            "samples": String(samples.count),
            "valueSamples": String(samples.compactMap(\.value).count),
            "successes": String(summary?.successCount ?? samples.filter(\.success).count),
            "failures": String(summary?.failureCount ?? samples.filter { !$0.success }.count),
        ]
        if let median = summary?.median {
            tags["median"] = String(format: "%.1f", median)
        }
        if let min = summary?.min {
            tags["min"] = String(format: "%.1f", min)
        }
        if let p95 = summary?.p95 {
            tags["p95"] = String(format: "%.1f", p95)
        }
        if let max = summary?.max {
            tags["max"] = String(format: "%.1f", max)
        }
        if let jitter = summary?.jitter {
            tags["jitter"] = String(format: "%.1f", jitter)
        }
        if let latestStatus = latest.tags["status"] {
            tags["status"] = latestStatus
        }
        if let latestError = latest.tags["error"] {
            tags["error"] = latestError
        }

        return NetworkMetricSample(
            id: first.id,
            date: Date(timeIntervalSince1970: key.bucketStart + coalescingInterval),
            kind: first.kind,
            sourceID: first.sourceID,
            sourceName: latest.sourceName,
            value: summary?.average ?? latest.value,
            secondaryValue: summary?.secondaryAverage ?? latest.secondaryValue,
            unit: first.unit,
            success: (summary?.failureCount ?? 0) == 0,
            route: first.route,
            networkID: latest.networkID ?? first.networkID,
            interfaceName: latest.interfaceName ?? first.interfaceName,
            tags: tags
        )
    }

    private func summaries(
        for samples: [NetworkMetricSample],
        windowStart: Date,
        windowEnd: Date
    ) -> [NetworkMetricSummary] {
        let groups = Dictionary(grouping: samples) { sample in
            NetworkMetricGroupKey(
                kind: sample.kind,
                sourceID: sample.sourceID,
                route: sample.route,
                networkID: sample.networkID,
                unit: sample.unit
            )
        }

        return groups.values
            .compactMap { NetworkMetricSummary.make(samples: $0, windowStart: windowStart, windowEnd: windowEnd) }
            .sorted {
                if $0.kind == $1.kind {
                    return $0.sourceName < $1.sourceName
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
    }

    private func save(now: Date = Date()) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(samples)
            try data.write(to: fileURL, options: .atomic)
            lastSave = now
        } catch {
            // Metrics are supporting evidence. Losing one save must not affect live monitoring.
        }
    }

    private static func loadSamples(from fileURL: URL) -> [NetworkMetricSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([NetworkMetricSample].self, from: data)
        else { return [] }
        return decoded.sorted { $0.date < $1.date }
    }

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PingBar", isDirectory: true)
            .appendingPathComponent("network-metrics-v1.json")
    }
}

private struct NetworkMetricGroupKey: Hashable {
    let kind: NetworkMetricKind
    let sourceID: String
    let route: String?
    let networkID: String?
    let unit: NetworkMetricUnit
}

private struct NetworkMetricCoalescingKey: Hashable {
    let kind: NetworkMetricKind
    let sourceID: String
    let route: String?
    let networkID: String?
    let unit: NetworkMetricUnit
    let bucketStart: TimeInterval
}

private extension NetworkMetricKind {
    var isCoalescible: Bool {
        switch self {
        case .gatewayLatency, .externalLatency, .applicationLatency, .applicationPhaseLatency, .throughput, .wifiSignal:
            return true
        case .speedTestLatency, .speedTestDownload, .speedTestUpload:
            return false
        }
    }
}

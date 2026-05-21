import XCTest

final class NetworkMetricStoreTests: XCTestCase {
    func testStoresSamplesAndBuildsMedianP95FailureRollups() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 2_000)
        let store = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 1, now: now)
        let samples = [
            NetworkMetricSample.latency(date: now.addingTimeInterval(-40), host: "1.1.1.1", label: "Cloudflare", latencyMs: 100, isGateway: false, identity: nil),
            NetworkMetricSample.latency(date: now.addingTimeInterval(-30), host: "1.1.1.1", label: "Cloudflare", latencyMs: 120, isGateway: false, identity: nil),
            NetworkMetricSample.latency(date: now.addingTimeInterval(-20), host: "1.1.1.1", label: "Cloudflare", latencyMs: nil, isGateway: false, identity: nil),
            NetworkMetricSample.latency(date: now.addingTimeInterval(-10), host: "1.1.1.1", label: "Cloudflare", latencyMs: 300, isGateway: false, identity: nil),
        ]

        let snapshot = store.record(samples, now: now)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .externalLatency && $0.sourceID == "1.1.1.1" })

        XCTAssertEqual(summary.sampleCount, 4)
        XCTAssertEqual(summary.successCount, 3)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.failureRate, 0.25)
        XCTAssertEqual(summary.median ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(summary.p95 ?? 0, 282, accuracy: 0.01)
        XCTAssertEqual(summary.jitter ?? 0, 100, accuracy: 0.01)
    }

    func testJitterCapturesLatencyVarianceWhenMedianLooksNormal() throws {
        let now = Date(timeIntervalSince1970: 2_500)
        let samples = [20, 22, 180, 24, 26].enumerated().map { index, latency in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(index)),
                host: "192.168.1.1",
                label: "Gateway",
                latencyMs: Double(latency),
                isGateway: true,
                identity: nil
            )
        }

        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(summary.median ?? 0, 24, accuracy: 0.01)
        XCTAssertGreaterThan(summary.jitter ?? 0, 75)
    }

    func testPersistsAndReloadsSamples() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 3_000)
        let store = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 1, now: now)
        _ = store.record(
            NetworkMetricSample.latency(
                date: now,
                host: "192.168.1.1",
                label: "Gateway",
                latencyMs: 8,
                isGateway: true,
                identity: nil
            ),
            now: now
        )
        store.flush()

        let reloaded = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 1, now: now.addingTimeInterval(1))
        let snapshot = reloaded.snapshot(window: 60, endingAt: now.addingTimeInterval(1))

        XCTAssertEqual(snapshot.samples.count, 1)
        let summary = try XCTUnwrap(snapshot.summaries.first)
        XCTAssertEqual(summary.kind, .gatewayLatency)
        XCTAssertEqual(summary.latestValue ?? 0, 8, accuracy: 0.01)
    }

    func testReloadPrunesExpiredSamplesBeforeBuildingSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 4_000)
        let encoder = JSONEncoder()
        let samples = [
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(-120),
                host: "old",
                label: "Old",
                latencyMs: 500,
                isGateway: false,
                identity: nil
            ),
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(-10),
                host: "fresh",
                label: "Fresh",
                latencyMs: 30,
                isGateway: false,
                identity: nil
            ),
        ]
        try encoder.encode(samples).write(to: fileURL, options: .atomic)

        let reloaded = NetworkMetricStore(
            fileURL: fileURL,
            retention: 60,
            maxSamples: 100,
            saveInterval: 3_600,
            now: now
        )
        let snapshot = reloaded.snapshot(window: 300, endingAt: now)

        XCTAssertEqual(snapshot.samples.map(\.sourceID), ["fresh"])
    }

    func testReloadPersistsNormalizedSampleCap() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 5_000)
        let samples = (0..<6).map { index in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(index)),
                host: "1.1.1.\(index)",
                label: "Host \(index)",
                latencyMs: Double(20 + index),
                isGateway: false,
                identity: nil
            )
        }
        try JSONEncoder().encode(samples).write(to: fileURL, options: .atomic)

        let reloaded = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            maxSamples: 3,
            saveInterval: 3_600,
            now: now.addingTimeInterval(10)
        )
        let snapshot = reloaded.snapshot(window: 60, endingAt: now.addingTimeInterval(10))
        let persisted = try JSONDecoder().decode(
            [NetworkMetricSample].self,
            from: Data(contentsOf: fileURL)
        )

        XCTAssertEqual(snapshot.samples.map(\.sourceID), ["1.1.1.3", "1.1.1.4", "1.1.1.5"])
        XCTAssertEqual(persisted.map(\.sourceID), ["1.1.1.3", "1.1.1.4", "1.1.1.5"])
    }

    func testFlushPersistsBeforeSaveInterval() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 3_500)
        let store = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 3_600, now: now)
        _ = store.record(
            NetworkMetricSample.latency(
                date: now,
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: 42,
                isGateway: false,
                identity: nil
            ),
            now: now
        )
        _ = store.record(
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(10),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: 84,
                isGateway: false,
                identity: nil
            ),
            now: now.addingTimeInterval(10)
        )

        let beforeFlush = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 3_600, now: now.addingTimeInterval(11))
            .snapshot(window: 60, endingAt: now.addingTimeInterval(11))
        XCTAssertEqual(beforeFlush.samples.count, 1)

        store.flush()
        let reloaded = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 3_600, now: now.addingTimeInterval(11))
        let snapshot = reloaded.snapshot(window: 60, endingAt: now.addingTimeInterval(11))
        let summary = try XCTUnwrap(snapshot.summaries.first)

        XCTAssertEqual(snapshot.samples.count, 2)
        XCTAssertEqual(summary.kind, .externalLatency)
        XCTAssertEqual(summary.latestValue ?? 0, 84, accuracy: 0.01)
    }

    func testResetAllowsImmediatePersistOnSampleTimeline() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 4_200)
        let store = NetworkMetricStore(fileURL: fileURL, retention: 3_600, maxSamples: 100, saveInterval: 3_600, now: now)
        _ = store.record(
            NetworkMetricSample.latency(
                date: now,
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: 42,
                isGateway: false,
                identity: nil
            ),
            now: now
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        _ = store.reset(now: now.addingTimeInterval(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        _ = store.record(
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(2),
                host: "8.8.8.8",
                label: "Google",
                latencyMs: 64,
                isGateway: false,
                identity: nil
            ),
            now: now.addingTimeInterval(2)
        )

        let persisted = try JSONDecoder().decode(
            [NetworkMetricSample].self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(persisted.map(\.sourceID), ["8.8.8.8"])
    }

    func testPrunesOldSamplesAndCapsStore() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(fileURL: fileURL, retention: 60, maxSamples: 3, saveInterval: 1)
        let samples = (0..<6).map { index in
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(Double(index - 5) * 20),
                host: "8.8.8.8",
                label: "Google",
                latencyMs: Double(100 + index),
                isGateway: false,
                identity: nil
            )
        }

        let snapshot = store.record(samples, now: now)

        XCTAssertEqual(snapshot.samples.count, 3)
        XCTAssertEqual(snapshot.samples.compactMap(\.value), [103, 104, 105])
    }

    func testCoalescesOlderHighFrequencySamplesIntoBuckets() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = makeExternalLatencySamples(offsets: Array(stride(from: 0, to: 900, by: 60)))

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let coalesced = snapshot.samples.filter { $0.tags["coalesced"] == "true" }
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .externalLatency && $0.sourceID == "1.1.1.1" })

        XCTAssertEqual(coalesced.count, 3)
        XCTAssertTrue(coalesced.allSatisfy { $0.tags["samples"] == "5" })
        XCTAssertEqual(summary.sampleCount, 15)
    }

    func testCoalescedSamplesContributeOriginalCountsToSummaries() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = makeExternalLatencySamples(values: [100, 101, nil, 103, 104])

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .externalLatency && $0.sourceID == "1.1.1.1" })

        XCTAssertEqual(snapshot.samples.count, 1)
        XCTAssertEqual(summary.sampleCount, 5)
        XCTAssertEqual(summary.successCount, 4)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.failureRate, 0.2)
        XCTAssertEqual(summary.average ?? 0, 102, accuracy: 0.01)
    }

    func testSummaryUsesWeightedCoalescedCountsWithoutExpandingArrays() throws {
        let now = Date(timeIntervalSince1970: 10_100)
        let coalesced = NetworkMetricSample(
            date: now,
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 100,
            unit: .milliseconds,
            success: true,
            tags: [
                "coalesced": "true",
                "samples": "1000",
                "valueSamples": "1000",
                "successes": "1000",
                "failures": "0",
                "median": "100",
                "p95": "100",
            ]
        )
        let spike = NetworkMetricSample(
            date: now.addingTimeInterval(1),
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 1_000,
            unit: .milliseconds,
            success: true
        )

        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: [coalesced, spike],
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(summary.sampleCount, 1_001)
        XCTAssertEqual(summary.median ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(summary.p95 ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(summary.average ?? 0, 100.899, accuracy: 0.01)
    }

    func testSummaryClampsCorruptCoalescedCountsAndFallsBackOnInvalidOutcomeTotals() throws {
        let now = Date(timeIntervalSince1970: 10_200)
        let corrupt = NetworkMetricSample(
            date: now,
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 100,
            unit: .milliseconds,
            success: false,
            tags: [
                "coalesced": "true",
                "samples": "999999999",
                "valueSamples": "999999999",
                "successes": "999999999",
                "failures": "999999999",
            ]
        )

        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: [corrupt],
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(summary.sampleCount, 1_000)
        XCTAssertEqual(summary.successCount, 0)
        XCTAssertEqual(summary.failureCount, 1_000)
        XCTAssertEqual(summary.average ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(summary.p95 ?? 0, 100, accuracy: 0.01)
    }

    func testRawSamplesIgnorePersistedCoalescingCountTags() throws {
        let now = Date(timeIntervalSince1970: 10_250)
        let raw = NetworkMetricSample(
            date: now,
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 100,
            unit: .milliseconds,
            success: true,
            tags: [
                "samples": "999",
                "valueSamples": "999",
                "successes": "999",
                "failures": "0",
                "median": "900",
                "p95": "900",
            ]
        )
        let spike = NetworkMetricSample(
            date: now.addingTimeInterval(1),
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 1_000,
            unit: .milliseconds,
            success: true
        )

        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: [raw, spike],
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.failureCount, 0)
        XCTAssertEqual(summary.median ?? 0, 550, accuracy: 0.01)
        XCTAssertEqual(summary.p95 ?? 0, 955, accuracy: 0.01)
        XCTAssertEqual(summary.average ?? 0, 550, accuracy: 0.01)
    }

    func testCoalescedValueSampleCountCannotExceedSampleCount() throws {
        let now = Date(timeIntervalSince1970: 10_260)
        let coalesced = NetworkMetricSample(
            date: now,
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 100,
            unit: .milliseconds,
            success: true,
            tags: [
                "coalesced": "true",
                "samples": "3",
                "valueSamples": "999",
                "successes": "3",
                "failures": "0",
                "median": "100",
                "p95": "100",
            ]
        )
        let spike = NetworkMetricSample(
            date: now.addingTimeInterval(1),
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            sourceName: "Cloudflare",
            value: 1_000,
            unit: .milliseconds,
            success: true
        )

        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: [coalesced, spike],
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(summary.sampleCount, 4)
        XCTAssertEqual(summary.average ?? 0, 325, accuracy: 0.01)
        XCTAssertEqual(summary.median ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(summary.p95 ?? 0, 865, accuracy: 0.01)
    }

    func testCoalescedSamplesPreserveLatencySpikesForP95Summaries() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = [100, 110, 120, 130, 1_200].enumerated().map { index, value in
            NetworkMetricSample.latency(
                date: Date(timeIntervalSince1970: Double(8_400 + index * 60)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: Double(value),
                isGateway: false,
                identity: nil
            )
        }

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let stored = try XCTUnwrap(snapshot.samples.first)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .externalLatency && $0.sourceID == "1.1.1.1" })

        XCTAssertEqual(stored.tags["max"], "1200.0")
        XCTAssertNotNil(stored.tags["jitter"])
        XCTAssertGreaterThan(summary.p95 ?? 0, AppConfig.defaultExternalLatencyCritical)
        XCTAssertLessThan(summary.average ?? 0, 400)
    }

    func testCoalescedSamplesPreserveMedianSeparatelyFromP95() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = [20, 22, 24, 26, 500].enumerated().map { index, value in
            NetworkMetricSample.latency(
                date: Date(timeIntervalSince1970: Double(8_400 + index * 60)),
                host: "1.1.1.1",
                label: "Cloudflare",
                latencyMs: Double(value),
                isGateway: false,
                identity: nil
            )
        }

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let stored = try XCTUnwrap(snapshot.samples.first)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .externalLatency && $0.sourceID == "1.1.1.1" })

        XCTAssertEqual(stored.tags["median"], "24.0")
        let storedP95 = try XCTUnwrap(stored.tags["p95"].flatMap(Double.init))
        XCTAssertGreaterThan(storedP95, 400)
        XCTAssertEqual(summary.median ?? 0, 24, accuracy: 0.01)
        XCTAssertGreaterThan(summary.p95 ?? 0, 400)
    }

    func testCoalescedJitterRepresentsInternalBucketVariance() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = [20, 120, 30, 130, 40].enumerated().map { index, value in
            NetworkMetricSample.latency(
                date: Date(timeIntervalSince1970: Double(8_400 + index * 60)),
                host: "192.168.1.1",
                label: "Gateway",
                latencyMs: Double(value),
                isGateway: true,
                identity: nil
            )
        }

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let stored = try XCTUnwrap(snapshot.samples.first)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .gatewayLatency && $0.sourceID == "192.168.1.1" })

        XCTAssertNotNil(stored.tags["jitter"])
        XCTAssertGreaterThan(summary.jitter ?? 0, 90)
    }

    func testCoalescedSamplesAreNotCoalescedAgainOnLaterWrites() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = makeExternalLatencySamples(offsets: Array(stride(from: 0, to: 300, by: 60)))
        _ = store.record(oldSamples, now: now)
        let firstSnapshot = store.snapshot(window: 3_600, endingAt: now)
        let firstCoalescedDates = firstSnapshot.samples
            .filter { $0.tags["coalesced"] == "true" }
            .map(\.date)

        _ = store.record(
            NetworkMetricSample.latency(
                date: now.addingTimeInterval(1),
                host: "8.8.8.8",
                label: "Google",
                latencyMs: 40,
                isGateway: false,
                identity: nil
            ),
            now: now.addingTimeInterval(1)
        )
        let laterSnapshot = store.snapshot(window: 3_600, endingAt: now.addingTimeInterval(1))
        let laterCoalescedDates = laterSnapshot.samples
            .filter { $0.tags["coalesced"] == "true" }
            .map(\.date)

        XCTAssertEqual(laterCoalescedDates, firstCoalescedDates)
    }

    func testSampleCapPreservesCoalescedRollupsBeforeRawSamples() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 4,
            saveInterval: 3_600
        )
        let oldSamples = makeExternalLatencySamples(offsets: Array(stride(from: 0, to: 900, by: 60)))
        _ = store.record(oldSamples, now: now)

        let rawSample = NetworkMetricSample.latency(
            date: now.addingTimeInterval(-10),
            host: "8.8.8.8",
            label: "Google",
            latencyMs: 40,
            isGateway: false,
            identity: nil
        )
        _ = store.record([rawSample], now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)

        XCTAssertEqual(snapshot.samples.count, 4)
        XCTAssertEqual(snapshot.samples.filter { $0.tags["coalesced"] == "true" }.count, 3)
        XCTAssertTrue(snapshot.samples.contains { $0.sourceID == "8.8.8.8" })
    }

    func testDoesNotCoalesceSpeedTestEvents() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let samples = (0..<5).map { index in
            NetworkMetricSample.speedTest(
                date: now.addingTimeInterval(Double(index * 60 - 1_500)),
                kind: .speedTestDownload,
                value: Double(100_000_000 + index),
                server: "Test",
                location: "Lab",
                status: "ok",
                identity: nil,
                noProxy: false
            )
        }

        _ = store.record(samples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)

        XCTAssertEqual(snapshot.samples.count, 5)
        XCTAssertFalse(snapshot.samples.contains { $0.tags["coalesced"] == "true" })
    }

    func testApplicationProbeSamplesPreservePhaseTags() {
        let probe = ApplicationProbe(
            id: "app",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 240,
            phaseMetrics: ApplicationProbePhaseMetrics(
                dnsMs: 8.4,
                connectMs: 32.2,
                tlsMs: 44.9,
                responseMs: 3.1,
                ttfbMs: 120.6,
                protocolName: "h2",
                isProxyConnection: true,
                isReusedConnection: false
            ),
            statusCode: 204,
            error: nil,
            date: Date(timeIntervalSince1970: 4_000)
        )

        let sample = NetworkMetricSample.applicationProbe(result, identity: nil)

        XCTAssertEqual(sample.tags["dnsMs"], "8.4")
        XCTAssertEqual(sample.tags["connectMs"], "32.2")
        XCTAssertEqual(sample.tags["tlsMs"], "44.9")
        XCTAssertEqual(sample.tags["ttfbMs"], "120.6")
        XCTAssertEqual(sample.tags["responseMs"], "3.1")
        XCTAssertEqual(sample.tags["protocol"], "h2")
        XCTAssertEqual(sample.tags["proxyConnection"], "true")
        XCTAssertEqual(sample.tags["reusedConnection"], "false")
    }

    func testApplicationProbePhaseSamplesBecomeSeparateTimeSeries() {
        let probe = ApplicationProbe(
            id: "app",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 240,
            phaseMetrics: ApplicationProbePhaseMetrics(
                dnsMs: 8.4,
                connectMs: 32.2,
                tlsMs: 44.9,
                requestMs: 2.0,
                responseMs: 3.1,
                ttfbMs: 120.6,
                protocolName: "h2",
                isProxyConnection: true,
                isReusedConnection: false
            ),
            statusCode: 204,
            error: nil,
            date: Date(timeIntervalSince1970: 4_000)
        )

        let samples = NetworkMetricSample.applicationProbePhaseSamples(result, identity: nil)

        XCTAssertEqual(samples.map(\.kind), Array(repeating: .applicationPhaseLatency, count: 6))
        XCTAssertEqual(samples.map(\.sourceID), ["app:dns", "app:connect", "app:tls", "app:request", "app:ttfb", "app:response"])
        XCTAssertEqual(samples.first { $0.sourceID == "app:ttfb" }?.value, 120.6)
        XCTAssertEqual(samples.first { $0.sourceID == "app:ttfb" }?.sourceName, "App TTFB")
        XCTAssertEqual(samples.first { $0.sourceID == "app:ttfb" }?.tags["phase"], "ttfb")
        XCTAssertEqual(samples.first { $0.sourceID == "app:ttfb" }?.tags["protocol"], "h2")
        XCTAssertEqual(samples.first { $0.sourceID == "app:ttfb" }?.tags["proxyConnection"], "true")
    }

    func testApplicationPhaseSamplesCoalesceAsTimeSeriesEvidence() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkMetricStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date(timeIntervalSince1970: 10_000)
        let store = NetworkMetricStore(
            fileURL: fileURL,
            retention: 3_600,
            rawRetention: 600,
            coalescingInterval: 300,
            maxSamples: 100,
            saveInterval: 3_600
        )
        let oldSamples = [300, 600, 900, 1_200, 3_000].enumerated().map { index, value in
            NetworkMetricSample(
                date: Date(timeIntervalSince1970: Double(8_400 + index * 60)),
                kind: .applicationPhaseLatency,
                sourceID: "app:ttfb",
                sourceName: "App TTFB",
                value: Double(value),
                unit: .milliseconds,
                route: "system",
                tags: ["phase": "ttfb", "appID": "app"]
            )
        }

        _ = store.record(oldSamples, now: now)
        let snapshot = store.snapshot(window: 3_600, endingAt: now)
        let stored = try XCTUnwrap(snapshot.samples.first)
        let summary = try XCTUnwrap(snapshot.summaries.first { $0.kind == .applicationPhaseLatency && $0.sourceID == "app:ttfb" })

        XCTAssertEqual(stored.tags["coalesced"], "true")
        XCTAssertEqual(summary.sampleCount, 5)
        XCTAssertGreaterThan(summary.p95 ?? 0, 2_500)
        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .caution)
    }

    func testApplicationProbeSamplePersistsFallbackErrorWithoutMarkingHTTPFailure() {
        let probe = ApplicationProbe(
            id: "app",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let result = ApplicationProbeResult(
            probe: probe,
            durationMs: 180,
            phaseMetrics: nil,
            statusCode: 206,
            error: "HEAD failed: method not allowed",
            date: Date(timeIntervalSince1970: 4_500)
        )

        let sample = NetworkMetricSample.applicationProbe(result, identity: nil)

        XCTAssertTrue(sample.success)
        XCTAssertEqual(sample.value, 180)
        XCTAssertEqual(sample.tags["status"], "206")
        XCTAssertEqual(sample.tags["error"], "HEAD failed: method not allowed")
    }

    func testCurrentNetworkFilterKeepsCurrentAndGlobalSummariesOnly() throws {
        let now = Date(timeIntervalSince1970: 5_000)
        let current = try makeSummary(
            sourceID: "current",
            value: 20,
            networkID: "wifi:office",
            date: now
        )
        let previous = try makeSummary(
            sourceID: "previous",
            value: 300,
            networkID: "wifi:cafe",
            date: now
        )
        let global = try makeSummary(
            sourceID: "global",
            value: 40,
            networkID: nil,
            date: now
        )

        let filtered = NetworkMetricFilters.currentNetworkSummaries(
            [current, previous, global],
            currentNetworkID: "wifi:office"
        )

        XCTAssertEqual(filtered.map(\.sourceID), ["current", "global"])
    }

    func testCurrentNetworkFilterKeepsAllSummariesWithoutCurrentIdentity() throws {
        let now = Date(timeIntervalSince1970: 5_500)
        let current = try makeSummary(sourceID: "current", value: 20, networkID: "wifi:office", date: now)
        let previous = try makeSummary(sourceID: "previous", value: 300, networkID: "wifi:cafe", date: now)

        let filtered = NetworkMetricFilters.currentNetworkSummaries(
            [current, previous],
            currentNetworkID: nil
        )

        XCTAssertEqual(filtered.map(\.sourceID), ["current", "previous"])
    }

    func testMetricDiagnosticsUseLatestMatchingApplicationPhaseTags() throws {
        let now = Date(timeIntervalSince1970: 6_000)
        let older = NetworkMetricSample(
            date: now,
            kind: .applicationLatency,
            sourceID: "app",
            sourceName: "App",
            value: 200,
            unit: .milliseconds,
            route: "system",
            networkID: "wifi:office",
            tags: ["dnsMs": "50.0", "ttfbMs": "300.0"]
        )
        let newer = NetworkMetricSample(
            date: now.addingTimeInterval(10),
            kind: .applicationLatency,
            sourceID: "app",
            sourceName: "App",
            value: 180,
            unit: .milliseconds,
            route: "system",
            networkID: "wifi:office",
            tags: ["dnsMs": "8.0", "connectMs": "22.0", "ttfbMs": "90.0"]
        )
        let otherNetwork = NetworkMetricSample(
            date: now.addingTimeInterval(20),
            kind: .applicationLatency,
            sourceID: "app",
            sourceName: "App",
            value: 500,
            unit: .milliseconds,
            route: "system",
            networkID: "wifi:cafe",
            tags: ["dnsMs": "99.0", "ttfbMs": "999.0"]
        )
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: [older, newer],
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let labels = NetworkMetricDiagnostics.applicationPhaseLabels(
            samples: [older, newer, otherNetwork],
            summary: summary
        )

        XCTAssertEqual(labels, ["dns=8.0ms", "connect=22.0ms", "ttfb=90.0ms"])
    }

    func testMetricDiagnosticsFormatsValuesByUnit() {
        XCTAssertEqual(NetworkMetricDiagnostics.formattedValue(12.34, unit: .milliseconds), "12.3 ms")
        XCTAssertEqual(NetworkMetricDiagnostics.formattedValue(1_500_000, unit: .bytesPerSecond), "1.4 MB/s")
        XCTAssertEqual(NetworkMetricDiagnostics.formattedValue(12_500_000, unit: .bitsPerSecond), "12.5 Mbps")
        XCTAssertEqual(NetworkMetricDiagnostics.formattedValue(-67.4, unit: .decibelMilliwatts), "-67 dBm")
    }

    func testCompactRollupLineIncludesCountsP95FailuresAndJitter() throws {
        let now = Date(timeIntervalSince1970: 6_500)
        let samples = [
            NetworkMetricSample.latency(date: now, host: "1.1.1.1", label: "Cloudflare", latencyMs: 80, isGateway: false, identity: nil),
            NetworkMetricSample.latency(date: now.addingTimeInterval(1), host: "1.1.1.1", label: "Cloudflare", latencyMs: nil, isGateway: false, identity: nil),
            NetworkMetricSample.latency(date: now.addingTimeInterval(2), host: "1.1.1.1", label: "Cloudflare", latencyMs: 160, isGateway: false, identity: nil),
        ]
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        let line = NetworkMetricDiagnostics.compactRollupLine(summary)

        XCTAssertTrue(line.contains("External latency: Cloudflare"))
        XCTAssertTrue(line.contains("n=3"))
        XCTAssertTrue(line.contains("fail=33.3%"))
        XCTAssertTrue(line.contains("p95="))
        XCTAssertTrue(line.contains("jit="))
    }

    func testRollupSeverityBandsUseNetworkSpecificLatencyThresholds() throws {
        let now = Date(timeIntervalSince1970: 7_000)
        let moderateApp = try XCTUnwrap(makeApplicationSummary(
            probe: ApplicationProbe(
                id: "app-system",
                name: "App",
                url: "https://example.com/health",
                route: .system,
                enabled: true
            ),
            durations: [190, 200, 210],
            now: now
        ))
        let gateway = try makeSummary(
            kind: .gatewayLatency,
            sourceID: "gateway",
            value: 120,
            networkID: nil,
            date: now
        )
        let external = try makeSummary(
            kind: .externalLatency,
            sourceID: "1.1.1.1",
            value: 260,
            networkID: nil,
            date: now
        )

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: moderateApp), .good)
        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: gateway), .critical)
        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: external), .caution)
    }

    func testRollupSeverityBandUsesConfiguredGatewayThresholds() throws {
        let now = Date(timeIntervalSince1970: 7_250)
        let gateway = try makeSummary(
            kind: .gatewayLatency,
            sourceID: "gateway",
            value: 75,
            networkID: nil,
            date: now
        )
        let policy = NetworkMetricSeverityPolicy(
            gatewayLatencyCaution: 70,
            gatewayLatencyCritical: 90,
            externalLatencyCaution: AppConfig.defaultExternalLatencyCaution,
            externalLatencyCritical: AppConfig.defaultExternalLatencyCritical,
            appDirectLatencyCaution: AppConfig.defaultAppDirectLatencyCaution,
            appDirectLatencyCritical: AppConfig.defaultAppDirectLatencyCritical,
            appSystemLatencyCaution: AppConfig.defaultAppSystemLatencyCaution,
            appSystemLatencyCritical: AppConfig.defaultAppSystemLatencyCritical,
            failureRateCritical: 0.20,
            rssiCaution: -70,
            rssiCritical: -80
        )

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: gateway, policy: policy), .caution)
    }

    func testRollupSeverityBandUsesDefaultGatewayCriticalThreshold() throws {
        let now = Date(timeIntervalSince1970: 7_350)
        let gateway = try makeSummary(
            kind: .gatewayLatency,
            sourceID: "gateway",
            value: AppConfig.defaultGatewayLatencyCritical,
            networkID: nil,
            date: now
        )

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: gateway), .critical)
    }

    func testRollupSeverityBandTreatsSingleApplicationFailureAsCautionEvidence() throws {
        let now = Date(timeIntervalSince1970: 7_500)
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
        let samples = [
            ApplicationProbeResult(probe: probe, durationMs: 200, phaseMetrics: nil, statusCode: 200, error: nil, date: now),
            ApplicationProbeResult(probe: probe, durationMs: nil, phaseMetrics: nil, statusCode: nil, error: "timeout", date: now.addingTimeInterval(1)),
            ApplicationProbeResult(probe: probe, durationMs: 220, phaseMetrics: nil, statusCode: 200, error: nil, date: now.addingTimeInterval(2)),
        ].map { NetworkMetricSample.applicationProbe($0, identity: nil) }
        let summary = try XCTUnwrap(NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        ))

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .caution)
    }

    func testRollupSeverityBandTreatsSingleExternalPacketLossAsNeutralEvidence() throws {
        let now = Date(timeIntervalSince1970: 7_600)
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

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .good)
    }

    func testRollupSeverityBandDoesNotHideSevereLatencyBehindSingleFailure() throws {
        let now = Date(timeIntervalSince1970: 7_750)
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
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

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .critical)
    }

    func testRollupSeverityBandKeepsLowRateRepeatedApplicationFailuresAtCaution() throws {
        let now = Date(timeIntervalSince1970: 7_900)
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
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

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .caution)
    }

    func testRollupSeverityBandEscalatesCriticalRateApplicationFailures() throws {
        let now = Date(timeIntervalSince1970: 8_000)
        let probe = ApplicationProbe(
            id: "app-system",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )
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

        XCTAssertEqual(NetworkMetricDiagnostics.rollupSeverityBand(for: summary), .critical)
    }

    private func makeSummary(
        kind: NetworkMetricKind = .externalLatency,
        sourceID: String,
        value: Double,
        networkID: String?,
        date: Date
    ) throws -> NetworkMetricSummary {
        let sample = NetworkMetricSample(
            date: date,
            kind: kind,
            sourceID: sourceID,
            sourceName: sourceID,
            value: value,
            unit: .milliseconds,
            networkID: networkID
        )
        return try XCTUnwrap(NetworkMetricSummary.make(
            samples: [sample, sample, sample],
            windowStart: date.addingTimeInterval(-60),
            windowEnd: date.addingTimeInterval(60)
        ))
    }

    private func makeApplicationSummary(
        probe: ApplicationProbe,
        durations: [Double],
        now: Date
    ) -> NetworkMetricSummary? {
        let samples = durations.enumerated().map { offset, duration in
            NetworkMetricSample.applicationProbe(
                ApplicationProbeResult(
                    probe: probe,
                    durationMs: duration,
                    phaseMetrics: nil,
                    statusCode: 200,
                    error: nil,
                    date: now.addingTimeInterval(Double(offset))
                ),
                identity: nil
            )
        }
        return NetworkMetricSummary.make(
            samples: samples,
            windowStart: now.addingTimeInterval(-60),
            windowEnd: now.addingTimeInterval(60)
        )
    }

    private func makeExternalLatencySamples(offsets: [Int]) -> [NetworkMetricSample] {
        var samples: [NetworkMetricSample] = []
        samples.reserveCapacity(offsets.count)

        for offset in offsets {
            samples.append(
                NetworkMetricSample.latency(
                    date: Date(timeIntervalSince1970: TimeInterval(8_400 + offset)),
                    host: "1.1.1.1",
                    label: "Cloudflare",
                    latencyMs: Double(100 + offset / 60),
                    isGateway: false,
                    identity: nil
                )
            )
        }

        return samples
    }

    private func makeExternalLatencySamples(values: [Double?]) -> [NetworkMetricSample] {
        var samples: [NetworkMetricSample] = []
        samples.reserveCapacity(values.count)

        for (index, value) in values.enumerated() {
            samples.append(
                NetworkMetricSample.latency(
                    date: Date(timeIntervalSince1970: TimeInterval(8_400 + index * 60)),
                    host: "1.1.1.1",
                    label: "Cloudflare",
                    latencyMs: value,
                    isGateway: false,
                    identity: nil
                )
            )
        }

        return samples
    }
}

import XCTest

final class TrafficUsageStoreTests: XCTestCase {
    func testAccumulatesInterfaceDeltasBySSID() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let store = TrafficUsageStore(defaults: defaults, calendar: calendar)
        let wifi = WiFiInfo(ssid: "Office", bssid: "aa:bb:cc:dd:ee:ff")
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: wifi)
        let date = Date(timeIntervalSince1970: 1_000)

        var sample = ThroughputSample()
        sample.uploadDelta = 256
        sample.downloadDelta = 1_024
        var snapshot = store.record(sample: sample, identity: identity, date: date)

        sample.uploadDelta = 128
        sample.downloadDelta = 512
        snapshot = store.record(sample: sample, identity: identity, date: date.addingTimeInterval(1))

        let records = snapshot.records
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.displayName, "Office")
        XCTAssertEqual(record.uploadBytes, 384)
        XCTAssertEqual(record.downloadBytes, 1_536)
        XCTAssertEqual(record.totalBytes, 1_920)

        XCTAssertEqual(snapshot.buckets.count, 1)
        let bucket = try XCTUnwrap(snapshot.buckets.first)
        XCTAssertEqual(bucket.day, "1970-01-01")
        XCTAssertEqual(bucket.totalBytes, 1_920)
    }

    func testStoresDailyBucketsAndAggregatesBySSID() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let store = TrafficUsageStore(defaults: defaults, calendar: calendar)
        let wifi = WiFiInfo(ssid: "Studio", bssid: "11:22:33:44:55:66")
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: wifi)
        let secondAP = NetworkTrafficIdentity(
            interfaceName: "en0",
            interfaceLabel: "Wi-Fi",
            wifiInfo: WiFiInfo(ssid: "Studio", bssid: "77:88:99:aa:bb:cc")
        )

        var sample = ThroughputSample()
        sample.uploadDelta = 1_000
        sample.downloadDelta = 4_000
        _ = store.record(sample: sample, identity: identity, date: Date(timeIntervalSince1970: 1_000))

        sample.uploadDelta = 2_000
        sample.downloadDelta = 8_000
        _ = store.record(sample: sample, identity: identity, date: Date(timeIntervalSince1970: 90_000))

        sample.uploadDelta = 500
        sample.downloadDelta = 500
        let snapshot = store.record(sample: sample, identity: secondAP, date: Date(timeIntervalSince1970: 91_000))

        XCTAssertEqual(snapshot.records.count, 2)
        XCTAssertEqual(snapshot.buckets.count, 3)

        let aggregates = NetworkTrafficAggregate.make(
            records: snapshot.records,
            buckets: snapshot.buckets,
            groupedBy: .ssid,
            currentIdentity: secondAP
        )

        XCTAssertEqual(aggregates.count, 1)
        let aggregate = try XCTUnwrap(aggregates.first)
        XCTAssertEqual(aggregate.displayName, "Studio")
        XCTAssertEqual(aggregate.uploadBytes, 3_500)
        XCTAssertEqual(aggregate.downloadBytes, 12_500)
        XCTAssertEqual(aggregate.dayCount, 2)
        XCTAssertEqual(aggregate.networkCount, 2)
        XCTAssertTrue(aggregate.detail.contains("all time"))
        XCTAssertTrue(aggregate.isCurrent)

        let networkAggregates = NetworkTrafficAggregate.make(
            records: snapshot.records,
            buckets: snapshot.buckets,
            groupedBy: .network,
            currentIdentity: secondAP
        )
        XCTAssertEqual(networkAggregates.count, 2)
    }

    func testWiFiIdentityIgnoresSSIDFromDifferentInterface() {
        let wifi = WiFiInfo(interfaceName: "en1", ssid: "Office", bssid: "aa:bb:cc:dd:ee:ff")
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: wifi)

        XCTAssertEqual(identity.kind, .interface)
        XCTAssertEqual(identity.displayName, "Wi-Fi")
        XCTAssertEqual(identity.id, "interface:en0")
        XCTAssertNil(identity.ssid)
        XCTAssertNil(identity.bssid)
    }

    func testOutOfOrderTrafficSamplesDoNotMoveLastSeenBackward() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let store = TrafficUsageStore(defaults: defaults, calendar: calendar)
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: nil)
        let later = Date(timeIntervalSince1970: 10_000)
        let earlier = Date(timeIntervalSince1970: 9_000)

        var sample = ThroughputSample()
        sample.uploadDelta = 100
        sample.downloadDelta = 100
        _ = store.record(sample: sample, identity: identity, date: later)

        sample.uploadDelta = 50
        sample.downloadDelta = 50
        let snapshot = store.record(sample: sample, identity: identity, date: earlier)
        let record = try XCTUnwrap(snapshot.records.first)
        let bucket = try XCTUnwrap(snapshot.buckets.first)

        XCTAssertEqual(record.firstSeen, earlier)
        XCTAssertEqual(record.lastSeen, later)
        XCTAssertEqual(bucket.firstSeen, earlier)
        XCTAssertEqual(bucket.lastSeen, later)
        XCTAssertEqual(record.totalBytes, 300)
        XCTAssertEqual(bucket.totalBytes, 300)
    }

    func testReloadPrunesExpiredDailyBuckets() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 200 * 24 * 60 * 60)
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: nil)
        let oldDate = now.addingTimeInterval(-190 * 24 * 60 * 60)
        let freshDate = now.addingTimeInterval(-5 * 24 * 60 * 60)
        var oldBucket = NetworkTrafficUsageBucket(
            identity: identity,
            day: NetworkTrafficUsageBucket.dayKey(for: oldDate, calendar: calendar),
            date: oldDate
        )
        oldBucket.record(uploadDelta: 100, downloadDelta: 100, identity: identity, date: oldDate)
        var freshBucket = NetworkTrafficUsageBucket(
            identity: identity,
            day: NetworkTrafficUsageBucket.dayKey(for: freshDate, calendar: calendar),
            date: freshDate
        )
        freshBucket.record(uploadDelta: 300, downloadDelta: 700, identity: identity, date: freshDate)

        let data = try JSONEncoder().encode([oldBucket, freshBucket])
        defaults.set(data, forKey: "networkTrafficUsageDailyBuckets_v1")

        let store = TrafficUsageStore(defaults: defaults, calendar: calendar, now: now)

        XCTAssertEqual(store.currentSnapshot.buckets.map(\.id), [freshBucket.id])
    }

    func testReloadCapsStoredRecordsAndPersistsNormalizedSet() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 10_000)
        let records = (0..<513).map { index in
            let identity = NetworkTrafficIdentity(
                interfaceName: "en\(index)",
                interfaceLabel: "Interface \(index)",
                wifiInfo: nil
            )
            var usage = NetworkTrafficUsage(identity: identity, date: now.addingTimeInterval(Double(index)))
            usage.record(
                uploadDelta: Int64(index + 1),
                downloadDelta: 0,
                identity: identity,
                date: now.addingTimeInterval(Double(index))
            )
            return usage
        }
        defaults.set(try JSONEncoder().encode(records), forKey: "networkTrafficUsage_v1")

        let store = TrafficUsageStore(defaults: defaults, calendar: calendar, now: now)
        let storedData = try XCTUnwrap(defaults.data(forKey: "networkTrafficUsage_v1"))
        let persisted = try JSONDecoder().decode([NetworkTrafficUsage].self, from: storedData)

        XCTAssertEqual(store.currentSnapshot.records.count, 512)
        XCTAssertEqual(persisted.count, 512)
        XCTAssertEqual(store.currentSnapshot.records.first?.id, "interface:en512")
        XCTAssertEqual(persisted.first?.id, "interface:en512")
    }

    func testSaveThrottleUsesSampleDateNotWallClock() throws {
        let suiteName = "TrafficUsageStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TrafficUsageStore(defaults: defaults)
        let identity = NetworkTrafficIdentity(interfaceName: "en0", interfaceLabel: "Wi-Fi", wifiInfo: nil)
        var sample = ThroughputSample()
        sample.uploadDelta = 100
        sample.downloadDelta = 100

        _ = store.record(sample: sample, identity: identity, date: Date(timeIntervalSince1970: 1_000))
        _ = store.record(sample: sample, identity: identity, date: Date(timeIntervalSince1970: 1_005))
        var storedData = try XCTUnwrap(defaults.data(forKey: "networkTrafficUsage_v1"))
        var persisted = try JSONDecoder().decode([NetworkTrafficUsage].self, from: storedData)
        XCTAssertEqual(persisted.first?.totalBytes, 200)

        _ = store.record(sample: sample, identity: identity, date: Date(timeIntervalSince1970: 1_011))
        storedData = try XCTUnwrap(defaults.data(forKey: "networkTrafficUsage_v1"))
        persisted = try JSONDecoder().decode([NetworkTrafficUsage].self, from: storedData)
        XCTAssertEqual(persisted.first?.totalBytes, 600)
    }
}

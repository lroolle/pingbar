import Foundation

final class TrafficUsageStore {
    private let defaults: UserDefaults
    private let recordsKey = "networkTrafficUsage_v1"
    private let bucketsKey = "networkTrafficUsageDailyBuckets_v1"
    private let maxRecords = 512
    private let maxBuckets = 4096
    private let maxBucketAgeDays = 180
    private let saveInterval: TimeInterval = 10
    private let calendar: Calendar
    private var records: [NetworkTrafficUsage]
    private var buckets: [NetworkTrafficUsageBucket]
    private var lastSave = Date.distantPast

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar
        let loadedRecords = Self.loadRecords(from: defaults, key: recordsKey)
        records = Array(Self.sortedRecords(loadedRecords).prefix(maxRecords))
        var shouldSave = records != loadedRecords
        buckets = Self.loadBuckets(from: defaults, key: bucketsKey)
        if buckets.isEmpty, !records.isEmpty {
            buckets = records.map { record in
                NetworkTrafficUsageBucket(
                    usage: record,
                    day: NetworkTrafficUsageBucket.dayKey(for: record.lastSeen, calendar: calendar)
                )
            }
            shouldSave = true
        }
        let loadedBuckets = buckets
        buckets = prunedBuckets(referenceDate: now)
        if buckets != loadedBuckets {
            shouldSave = true
        }
        if shouldSave {
            save(now: now)
        }
    }

    var currentRecords: [NetworkTrafficUsage] {
        currentSnapshot.records
    }

    var currentSnapshot: NetworkTrafficUsageSnapshot {
        NetworkTrafficUsageSnapshot(
            records: Self.sortedRecords(records),
            buckets: Self.sortedBuckets(buckets)
        )
    }

    @discardableResult
    func record(sample: ThroughputSample, identity: NetworkTrafficIdentity, date: Date = Date()) -> NetworkTrafficUsageSnapshot {
        guard sample.uploadDelta > 0 || sample.downloadDelta > 0 else {
            return currentSnapshot
        }

        if let index = records.firstIndex(where: { $0.id == identity.id }) {
            records[index].record(
                uploadDelta: sample.uploadDelta,
                downloadDelta: sample.downloadDelta,
                identity: identity,
                date: date
            )
        } else {
            var usage = NetworkTrafficUsage(identity: identity, date: date)
            usage.record(
                uploadDelta: sample.uploadDelta,
                downloadDelta: sample.downloadDelta,
                identity: identity,
                date: date
            )
            records.append(usage)
        }

        let day = NetworkTrafficUsageBucket.dayKey(for: date, calendar: calendar)
        let bucketID = "\(identity.id)|\(day)"
        if let index = buckets.firstIndex(where: { $0.id == bucketID }) {
            buckets[index].record(
                uploadDelta: sample.uploadDelta,
                downloadDelta: sample.downloadDelta,
                identity: identity,
                date: date
            )
        } else {
            var bucket = NetworkTrafficUsageBucket(identity: identity, day: day, date: date)
            bucket.record(
                uploadDelta: sample.uploadDelta,
                downloadDelta: sample.downloadDelta,
                identity: identity,
                date: date
            )
            buckets.append(bucket)
        }

        records = Array(Self.sortedRecords(records).prefix(maxRecords))
        buckets = prunedBuckets(referenceDate: date)
        if date.timeIntervalSince(lastSave) >= saveInterval || sample.uploadDelta + sample.downloadDelta >= 1_048_576 {
            save(now: date)
        }
        return currentSnapshot
    }

    @discardableResult
    func reset() -> NetworkTrafficUsageSnapshot {
        records = []
        buckets = []
        defaults.removeObject(forKey: recordsKey)
        defaults.removeObject(forKey: bucketsKey)
        lastSave = Date.distantPast
        return currentSnapshot
    }

    func flush() {
        save(now: Date())
    }

    private func save(now: Date) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
        if let data = try? encoder.encode(buckets) {
            defaults.set(data, forKey: bucketsKey)
        }
        lastSave = now
    }

    private static func sortedRecords(_ records: [NetworkTrafficUsage]) -> [NetworkTrafficUsage] {
        records.sorted {
            if $0.totalBytes == $1.totalBytes {
                return $0.lastSeen > $1.lastSeen
            }
            return $0.totalBytes > $1.totalBytes
        }
    }

    private static func sortedBuckets(_ buckets: [NetworkTrafficUsageBucket]) -> [NetworkTrafficUsageBucket] {
        buckets.sorted {
            if $0.lastSeen == $1.lastSeen {
                return $0.totalBytes > $1.totalBytes
            }
            return $0.lastSeen > $1.lastSeen
        }
    }

    private func prunedBuckets(referenceDate: Date) -> [NetworkTrafficUsageBucket] {
        let cutoff = calendar.date(byAdding: .day, value: -maxBucketAgeDays, to: referenceDate) ?? Date.distantPast
        let recent = buckets.filter { $0.lastSeen >= cutoff }
        return Array(Self.sortedBuckets(recent).prefix(maxBuckets))
    }

    private static func loadRecords(from defaults: UserDefaults, key: String) -> [NetworkTrafficUsage] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([NetworkTrafficUsage].self, from: data)
        else { return [] }
        return decoded
    }

    private static func loadBuckets(from defaults: UserDefaults, key: String) -> [NetworkTrafficUsageBucket] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([NetworkTrafficUsageBucket].self, from: data)
        else { return [] }
        return decoded
    }
}

import Foundation

enum NetworkTrafficKind: String, Codable, Hashable, Sendable {
    case wifi
    case interface

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .interface: return "Interface"
        }
    }
}

enum NetworkTrafficAggregation: String, CaseIterable, Hashable, Identifiable, Sendable {
    case network
    case ssid
    case interface

    var id: String { rawValue }

    var label: String {
        switch self {
        case .network: return "Network"
        case .ssid: return "SSID"
        case .interface: return "Interface"
        }
    }
}

struct NetworkTrafficIdentity: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: NetworkTrafficKind
    let interfaceName: String
    let interfaceLabel: String?
    let ssid: String?
    let bssid: String?

    init(
        interfaceName: String,
        interfaceLabel: String?,
        wifiInfo: WiFiInfo?
    ) {
        self.interfaceName = interfaceName
        self.interfaceLabel = interfaceLabel
        let matchingWiFiInfo: WiFiInfo?
        if let wifiInterface = wifiInfo?.interfaceName, wifiInterface != interfaceName {
            matchingWiFiInfo = nil
        } else {
            matchingWiFiInfo = wifiInfo
        }

        ssid = matchingWiFiInfo?.ssid
        bssid = matchingWiFiInfo?.bssid

        if let ssid = matchingWiFiInfo?.ssid, !ssid.isEmpty {
            kind = .wifi
            displayName = ssid
            if let bssid = matchingWiFiInfo?.bssid, !bssid.isEmpty {
                id = "wifi:\(Self.stableKey(ssid)):\(Self.stableKey(bssid))"
            } else {
                id = "wifi:\(Self.stableKey(ssid))"
            }
        } else {
            kind = .interface
            displayName = interfaceLabel ?? interfaceName
            id = "interface:\(interfaceName)"
        }
    }

    static func stableKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

struct NetworkTrafficUsageBucket: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var networkID: String
    var networkDisplayName: String
    var kind: NetworkTrafficKind
    var interfaceName: String
    var interfaceLabel: String?
    var ssid: String?
    var bssid: String?
    var day: String
    var uploadBytes: Int64
    var downloadBytes: Int64
    var firstSeen: Date
    var lastSeen: Date

    init(identity: NetworkTrafficIdentity, day: String, date: Date) {
        id = "\(identity.id)|\(day)"
        networkID = identity.id
        networkDisplayName = identity.displayName
        kind = identity.kind
        interfaceName = identity.interfaceName
        interfaceLabel = identity.interfaceLabel
        ssid = identity.ssid
        bssid = identity.bssid
        self.day = day
        uploadBytes = 0
        downloadBytes = 0
        firstSeen = date
        lastSeen = date
    }

    init(usage: NetworkTrafficUsage, day: String) {
        id = "\(usage.id)|\(day)"
        networkID = usage.id
        networkDisplayName = usage.displayName
        kind = usage.kind
        interfaceName = usage.interfaceName
        interfaceLabel = usage.interfaceLabel
        ssid = usage.ssid
        bssid = usage.bssid
        self.day = day
        uploadBytes = usage.uploadBytes
        downloadBytes = usage.downloadBytes
        firstSeen = usage.firstSeen
        lastSeen = usage.lastSeen
    }

    var totalBytes: Int64 {
        uploadBytes + downloadBytes
    }

    mutating func record(uploadDelta: Int64, downloadDelta: Int64, identity: NetworkTrafficIdentity, date: Date) {
        networkID = identity.id
        networkDisplayName = identity.displayName
        kind = identity.kind
        interfaceName = identity.interfaceName
        interfaceLabel = identity.interfaceLabel
        ssid = identity.ssid
        bssid = identity.bssid
        uploadBytes += max(0, uploadDelta)
        downloadBytes += max(0, downloadDelta)
        if date < firstSeen { firstSeen = date }
        if date > lastSeen { lastSeen = date }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct NetworkTrafficUsage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String
    var kind: NetworkTrafficKind
    var interfaceName: String
    var interfaceLabel: String?
    var ssid: String?
    var bssid: String?
    var uploadBytes: Int64
    var downloadBytes: Int64
    var firstSeen: Date
    var lastSeen: Date

    init(identity: NetworkTrafficIdentity, date: Date) {
        id = identity.id
        displayName = identity.displayName
        kind = identity.kind
        interfaceName = identity.interfaceName
        interfaceLabel = identity.interfaceLabel
        ssid = identity.ssid
        bssid = identity.bssid
        uploadBytes = 0
        downloadBytes = 0
        firstSeen = date
        lastSeen = date
    }

    var totalBytes: Int64 {
        uploadBytes + downloadBytes
    }

    mutating func record(uploadDelta: Int64, downloadDelta: Int64, identity: NetworkTrafficIdentity, date: Date) {
        displayName = identity.displayName
        kind = identity.kind
        interfaceName = identity.interfaceName
        interfaceLabel = identity.interfaceLabel
        ssid = identity.ssid
        bssid = identity.bssid
        uploadBytes += max(0, uploadDelta)
        downloadBytes += max(0, downloadDelta)
        if date < firstSeen { firstSeen = date }
        if date > lastSeen { lastSeen = date }
    }
}

struct NetworkTrafficUsageSnapshot: Equatable, Sendable {
    let records: [NetworkTrafficUsage]
    let buckets: [NetworkTrafficUsageBucket]

    var isEmpty: Bool {
        records.isEmpty && buckets.isEmpty
    }
}

struct NetworkTrafficAggregate: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let detail: String
    let kind: NetworkTrafficKind
    let uploadBytes: Int64
    let downloadBytes: Int64
    let firstSeen: Date
    let lastSeen: Date
    let isCurrent: Bool
    let networkCount: Int
    let dayCount: Int

    var totalBytes: Int64 {
        uploadBytes + downloadBytes
    }

    static func make(
        records: [NetworkTrafficUsage],
        buckets: [NetworkTrafficUsageBucket],
        groupedBy aggregation: NetworkTrafficAggregation,
        currentIdentity: NetworkTrafficIdentity?
    ) -> [NetworkTrafficAggregate] {
        let currentGroupID = groupID(for: currentIdentity, groupedBy: aggregation)
        var groups: [String: NetworkTrafficAggregateAccumulator] = [:]

        if records.isEmpty {
            for bucket in buckets {
                let group = groupDescriptor(for: bucket, groupedBy: aggregation)
                if groups[group.id] == nil {
                    groups[group.id] = NetworkTrafficAggregateAccumulator(
                        id: group.id,
                        displayName: group.displayName,
                        baseDetail: group.detail,
                        kind: group.kind
                    )
                }
                groups[group.id]?.add(
                    bucket: bucket,
                    isCurrent: group.id == currentGroupID,
                    countTraffic: true
                )
            }
        } else {
            for record in records {
                let bucket = NetworkTrafficUsageBucket(
                    usage: record,
                    day: NetworkTrafficUsageBucket.dayKey(for: record.lastSeen)
                )
                let group = groupDescriptor(for: bucket, groupedBy: aggregation)
                if groups[group.id] == nil {
                    groups[group.id] = NetworkTrafficAggregateAccumulator(
                        id: group.id,
                        displayName: group.displayName,
                        baseDetail: group.detail,
                        kind: group.kind
                    )
                }
                groups[group.id]?.add(
                    bucket: bucket,
                    isCurrent: group.id == currentGroupID,
                    countTraffic: true,
                    countsAllTimeTraffic: true
                )
            }
        }

        for bucket in buckets {
            let group = groupDescriptor(for: bucket, groupedBy: aggregation)
            let shouldCountTraffic = groups[group.id] == nil
            if groups[group.id] == nil {
                groups[group.id] = NetworkTrafficAggregateAccumulator(
                    id: group.id,
                    displayName: group.displayName,
                    baseDetail: group.detail,
                    kind: group.kind
                )
            }
            groups[group.id]?.add(
                bucket: bucket,
                isCurrent: group.id == currentGroupID,
                countTraffic: shouldCountTraffic
            )
        }

        return groups.values
            .map { $0.aggregate() }
            .sorted {
                if $0.totalBytes == $1.totalBytes {
                    return $0.lastSeen > $1.lastSeen
                }
                return $0.totalBytes > $1.totalBytes
            }
    }

    private static func groupID(for identity: NetworkTrafficIdentity?, groupedBy aggregation: NetworkTrafficAggregation) -> String? {
        guard let identity else { return nil }
        switch aggregation {
        case .network:
            return identity.id
        case .ssid:
            if let ssid = identity.ssid, !ssid.isEmpty {
                return "ssid:\(NetworkTrafficIdentity.stableKey(ssid))"
            }
            return "network:\(identity.id)"
        case .interface:
            return "interface:\(identity.interfaceName)"
        }
    }

    private static func groupDescriptor(
        for bucket: NetworkTrafficUsageBucket,
        groupedBy aggregation: NetworkTrafficAggregation
    ) -> (id: String, displayName: String, detail: String, kind: NetworkTrafficKind) {
        switch aggregation {
        case .network:
            return (
                bucket.networkID,
                bucket.networkDisplayName,
                networkDetail(
                    kind: bucket.kind,
                    interfaceName: bucket.interfaceName,
                    interfaceLabel: bucket.interfaceLabel,
                    bssid: bucket.bssid
                ),
                bucket.kind
            )
        case .ssid:
            if let ssid = bucket.ssid, !ssid.isEmpty {
                return (
                    "ssid:\(NetworkTrafficIdentity.stableKey(ssid))",
                    ssid,
                    "SSID",
                    .wifi
                )
            }
            return (
                "network:\(bucket.networkID)",
                bucket.networkDisplayName,
                "No SSID",
                bucket.kind
            )
        case .interface:
            return (
                "interface:\(bucket.interfaceName)",
                bucket.interfaceLabel ?? bucket.interfaceName,
                bucket.interfaceName,
                .interface
            )
        }
    }

    private static func networkDetail(
        kind: NetworkTrafficKind,
        interfaceName: String,
        interfaceLabel: String?,
        bssid: String?
    ) -> String {
        let interfaceText = interfaceLabel?.isEmpty == false ? interfaceLabel! : interfaceName
        var parts = [kind.label]
        if !interfaceText.isEmpty, interfaceText != kind.label {
            parts.append(interfaceText)
        }
        if kind == .wifi, let ap = accessPointLabel(for: bssid) {
            parts.append(ap)
        }
        return parts.joined(separator: " · ")
    }

    private static func accessPointLabel(for bssid: String?) -> String? {
        guard let bssid, !bssid.isEmpty else { return nil }
        let parts = bssid.split(separator: ":")
        if parts.count >= 3 {
            return "AP " + parts.suffix(3).joined(separator: ":")
        }
        return "AP \(bssid)"
    }
}

private struct NetworkTrafficAggregateAccumulator {
    let id: String
    var displayName: String
    var baseDetail: String
    var kind: NetworkTrafficKind
    var uploadBytes: Int64 = 0
    var downloadBytes: Int64 = 0
    var firstSeen = Date.distantFuture
    var lastSeen = Date.distantPast
    var networkIDs = Set<String>()
    var days = Set<String>()
    var isCurrent = false
    var countsAllTimeTraffic = false

    mutating func add(
        bucket: NetworkTrafficUsageBucket,
        isCurrent: Bool,
        countTraffic: Bool,
        countsAllTimeTraffic: Bool = false
    ) {
        if countTraffic {
            uploadBytes += bucket.uploadBytes
            downloadBytes += bucket.downloadBytes
            if bucket.firstSeen < firstSeen { firstSeen = bucket.firstSeen }
            if bucket.lastSeen > lastSeen { lastSeen = bucket.lastSeen }
            self.countsAllTimeTraffic = self.countsAllTimeTraffic || countsAllTimeTraffic
        }
        networkIDs.insert(bucket.networkID)
        days.insert(bucket.day)
        self.isCurrent = self.isCurrent || isCurrent
    }

    func aggregate() -> NetworkTrafficAggregate {
        let dayText: String
        switch days.count {
        case 0: dayText = "total"
        case 1: dayText = "1 day"
        default: dayText = "\(days.count) days"
        }

        let timeText = countsAllTimeTraffic ? "all time" : dayText
        let routeText = networkIDs.count > 1 ? "\(networkIDs.count) networks" : baseDetail
        let detail = routeText.isEmpty ? timeText : "\(routeText) · \(timeText)"

        return NetworkTrafficAggregate(
            id: id,
            displayName: displayName,
            detail: detail,
            kind: kind,
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes,
            firstSeen: firstSeen == Date.distantFuture ? Date() : firstSeen,
            lastSeen: lastSeen == Date.distantPast ? Date() : lastSeen,
            isCurrent: isCurrent,
            networkCount: networkIDs.count,
            dayCount: days.count
        )
    }
}

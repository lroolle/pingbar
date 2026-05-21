import Foundation

final class AppConfig {
    static let shared = AppConfig()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateWarningThresholdDefaults()
    }

    var pingHosts: [PingHost] {
        get {
            guard let data = defaults.data(forKey: "pingHosts_v2"),
                  let hosts = try? JSONDecoder().decode([PingHost].self, from: data)
            else { return Self.defaultPingHosts }
            let normalized = Self.normalizedPingHosts(hosts)
            if normalized != hosts, let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: "pingHosts_v2")
            }
            return normalized
        }
        set {
            if let data = try? JSONEncoder().encode(Self.normalizedPingHosts(newValue)) {
                defaults.set(data, forKey: "pingHosts_v2")
            }
        }
    }

    var proxyProbes: [ProxyProbe] {
        get {
            guard let data = defaults.data(forKey: "proxyProbes_v1"),
                  let probes = try? JSONDecoder().decode([ProxyProbe].self, from: data)
            else { return Self.defaultProxyProbes }
            return probes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "proxyProbes_v1")
            }
        }
    }

    var publicIPProviders: [PublicIPProvider] {
        get {
            guard let data = defaults.data(forKey: "publicIPProviders_v1"),
                  let providers = try? JSONDecoder().decode([PublicIPProvider].self, from: data)
            else { return Self.defaultPublicIPProviders }
            let migrated = PublicIPProviderCatalog.normalized(providers)
            if migrated != providers, let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: "publicIPProviders_v1")
            }
            return migrated
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "publicIPProviders_v1")
            }
        }
    }

    var applicationProbes: [ApplicationProbe] {
        get {
            guard let data = defaults.data(forKey: "applicationProbes_v1"),
                  let probes = try? JSONDecoder().decode([ApplicationProbe].self, from: data)
            else { return Self.defaultApplicationProbes }
            return probes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "applicationProbes_v1")
            }
        }
    }

    var egressTraceTargets: [EgressTraceTarget] {
        get {
            guard let data = defaults.data(forKey: "egressTraceTargets_v1"),
                  let targets = try? JSONDecoder().decode([EgressTraceTarget].self, from: data)
            else { return Self.defaultEgressTraceTargets }
            return targets
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "egressTraceTargets_v1")
            }
        }
    }

    var ipInfoToken: String {
        get { defaults.string(forKey: "ipInfoToken") ?? "" }
        set { defaults.set(newValue, forKey: "ipInfoToken") }
    }

    var publicIPFamily: IPProbeFamily {
        get { IPProbeFamily(rawValue: defaults.string(forKey: "publicIPFamily") ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: "publicIPFamily") }
    }

    var pingInterval: TimeInterval {
        get { max(1, defaults.double(forKey: "pingInterval").nonZero ?? 2) }
        set { defaults.set(newValue, forKey: "pingInterval") }
    }

    var throughputInterval: TimeInterval {
        get { max(0.5, defaults.double(forKey: "throughputInterval").nonZero ?? 1) }
        set { defaults.set(newValue, forKey: "throughputInterval") }
    }

    var wifiInterval: TimeInterval {
        get { max(2, defaults.double(forKey: "wifiInterval").nonZero ?? 5) }
        set { defaults.set(newValue, forKey: "wifiInterval") }
    }

    var networkDetailsInterval: TimeInterval {
        get { max(5, defaults.double(forKey: "networkDetailsInterval").nonZero ?? 10) }
        set { defaults.set(newValue, forKey: "networkDetailsInterval") }
    }

    var processStatsInterval: TimeInterval {
        get { max(2, defaults.double(forKey: "processStatsInterval").nonZero ?? 3) }
        set { defaults.set(newValue, forKey: "processStatsInterval") }
    }

    var gatewayLatencyCaution: Double {
        get { boundedMilliseconds(forKey: "gatewayLatencyCaution", defaultValue: Self.defaultGatewayLatencyCaution) }
        set { setBoundedMilliseconds(newValue, forKey: "gatewayLatencyCaution") }
    }

    var gatewayLatencyCritical: Double {
        get { boundedMilliseconds(forKey: "gatewayLatencyCritical", defaultValue: Self.defaultGatewayLatencyCritical) }
        set { setBoundedMilliseconds(newValue, forKey: "gatewayLatencyCritical") }
    }

    var externalLatencyCaution: Double {
        get { boundedMilliseconds(forKey: "externalLatencyCaution", defaultValue: Self.defaultExternalLatencyCaution) }
        set { setBoundedMilliseconds(newValue, forKey: "externalLatencyCaution") }
    }

    var externalLatencyCritical: Double {
        get { boundedMilliseconds(forKey: "externalLatencyCritical", defaultValue: Self.defaultExternalLatencyCritical) }
        set { setBoundedMilliseconds(newValue, forKey: "externalLatencyCritical") }
    }

    var packetLossCaution: Double {
        get { boundedRatio(forKey: "packetLossCaution", defaultValue: Self.defaultPacketLossCaution) }
        set { setBoundedRatio(newValue, forKey: "packetLossCaution") }
    }

    var packetLossCritical: Double {
        get { boundedRatio(forKey: "packetLossCritical", defaultValue: Self.defaultPacketLossCritical) }
        set { setBoundedRatio(newValue, forKey: "packetLossCritical") }
    }

    var appDirectLatencyCaution: Double {
        get { boundedMilliseconds(forKey: "appDirectLatencyCaution", defaultValue: Self.defaultAppDirectLatencyCaution) }
        set { setBoundedMilliseconds(newValue, forKey: "appDirectLatencyCaution") }
    }

    var appDirectLatencyCritical: Double {
        get { boundedMilliseconds(forKey: "appDirectLatencyCritical", defaultValue: Self.defaultAppDirectLatencyCritical) }
        set { setBoundedMilliseconds(newValue, forKey: "appDirectLatencyCritical") }
    }

    var appSystemLatencyCaution: Double {
        get { boundedMilliseconds(forKey: "appSystemLatencyCaution", defaultValue: Self.defaultAppSystemLatencyCaution) }
        set { setBoundedMilliseconds(newValue, forKey: "appSystemLatencyCaution") }
    }

    var appSystemLatencyCritical: Double {
        get { boundedMilliseconds(forKey: "appSystemLatencyCritical", defaultValue: Self.defaultAppSystemLatencyCritical) }
        set { setBoundedMilliseconds(newValue, forKey: "appSystemLatencyCritical") }
    }

    var topProcessCount: Int {
        get { min(max(defaults.integer(forKey: "topProcessCount").nonZero ?? 6, 3), 10) }
        set { defaults.set(newValue, forKey: "topProcessCount") }
    }

    var showUploadInMenuBar: Bool {
        get { defaults.object(forKey: "showUploadInMenuBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showUploadInMenuBar") }
    }

    var showHealthDot: Bool {
        get { defaults.object(forKey: "showHealthDot") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showHealthDot") }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .stacked }
        set { defaults.set(newValue.rawValue, forKey: "menuBarStyle") }
    }

    var menuBarContentMode: MenuBarContentMode {
        get { MenuBarContentMode(rawValue: defaults.string(forKey: "menuBarContentMode") ?? "") ?? .speed }
        set { defaults.set(newValue.rawValue, forKey: "menuBarContentMode") }
    }

    var menuBarEgressSourceID: String {
        get { defaults.string(forKey: "menuBarEgressSourceID") ?? "" }
        set { defaults.set(newValue, forKey: "menuBarEgressSourceID") }
    }

    var menuBarTraceMaskIP: Bool {
        get { defaults.object(forKey: "menuBarTraceMaskIP") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceMaskIP") }
    }

    var menuBarTraceCompact: Bool {
        get { defaults.object(forKey: "menuBarTraceCompact") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceCompact") }
    }

    var menuBarTraceShowDestination: Bool {
        get { defaults.object(forKey: "menuBarTraceShowDestination") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceShowDestination") }
    }

    var menuBarTraceShowFlag: Bool {
        get { defaults.object(forKey: "menuBarTraceShowFlag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceShowFlag") }
    }

    var menuBarTraceShowCountryCode: Bool {
        get { defaults.object(forKey: "menuBarTraceShowCountryCode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "menuBarTraceShowCountryCode") }
    }

    var menuBarTraceShowColo: Bool {
        get { defaults.object(forKey: "menuBarTraceShowColo") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceShowColo") }
    }

    var menuBarTraceShowWarp: Bool {
        get { defaults.object(forKey: "menuBarTraceShowWarp") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarTraceShowWarp") }
    }

    var menuBarTraceShowGateway: Bool {
        get { defaults.object(forKey: "menuBarTraceShowGateway") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "menuBarTraceShowGateway") }
    }

    var menuBarTraceShowHTTP: Bool {
        get { defaults.object(forKey: "menuBarTraceShowHTTP") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "menuBarTraceShowHTTP") }
    }

    var menuBarFixedWidth: Bool {
        get { defaults.object(forKey: "menuBarFixedWidth") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarFixedWidth") }
    }

    var menuBarWidth: Double {
        get { max(88, defaults.double(forKey: "menuBarWidth").nonZero ?? 136) }
        set { defaults.set(newValue, forKey: "menuBarWidth") }
    }

    var stackedMenuBarWidth: Double {
        get { max(96, defaults.double(forKey: "stackedMenuBarWidth").nonZero ?? 108) }
        set { defaults.set(newValue, forKey: "stackedMenuBarWidth") }
    }

    var panelSectionOrder: [PanelSection] {
        get {
            guard let rawValues = defaults.array(forKey: "panelSectionOrder_v1") as? [String] else {
                return Self.defaultPanelSectionOrder
            }
            let sections = rawValues.compactMap(PanelSection.init(rawValue:))
            return Self.normalizedPanelSectionOrder(sections)
        }
        set {
            let sections = Self.normalizedPanelSectionOrder(newValue)
            defaults.set(sections.map(\.rawValue), forKey: "panelSectionOrder_v1")
        }
    }

    static let defaultPingHosts: [PingHost] = [
        PingHost(address: "1.1.1.1", label: "Cloudflare", enabled: true),
        PingHost(address: "8.8.8.8", label: "Google", enabled: true),
        PingHost(address: "223.5.5.5", label: "Alibaba", enabled: false),
        PingHost(address: "119.29.29.29", label: "Tencent", enabled: false),
    ]

    static func normalizedPingHosts(_ hosts: [PingHost]) -> [PingHost] {
        var seenIDs = Set<String>()
        var seenAddresses = Set<String>()
        var normalized: [PingHost] = []

        for host in hosts {
            var copy = host
            copy.address = copy.address.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.label = copy.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if copy.address.isEmpty || seenAddresses.contains(copy.address) {
                continue
            }
            if copy.label.isEmpty {
                copy.label = copy.address
            }
            if copy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || seenIDs.contains(copy.id) {
                copy.id = UUID().uuidString
            }
            seenIDs.insert(copy.id)
            seenAddresses.insert(copy.address)
            normalized.append(copy)
        }

        return normalized
    }

    static let defaultPanelSectionOrder: [PanelSection] = [
        .latency,
        .metricRollups,
        .throughput,
        .trafficUsage,
        .egress,
        .wifi,
        .processes,
        .speedTest,
        .speedHistory,
    ]

    static func normalizedPanelSectionOrder(_ sections: [PanelSection]) -> [PanelSection] {
        var normalized: [PanelSection] = []
        for section in sections where !normalized.contains(section) {
            normalized.append(section)
        }
        for section in defaultPanelSectionOrder where !normalized.contains(section) {
            if let defaultPrevious = nearestPresentDefaultPredecessor(of: section, in: normalized),
               let insertionIndex = normalized.firstIndex(of: defaultPrevious),
               insertionIndex == normalized.index(before: normalized.endIndex) {
                normalized.insert(section, at: insertionIndex + 1)
            } else if let defaultPrevious = nearestPresentDefaultPredecessor(of: section, in: normalized),
                      let defaultNext = nearestPresentDefaultSuccessor(of: section, in: normalized),
                      let previousIndex = normalized.firstIndex(of: defaultPrevious),
                      let nextIndex = normalized.firstIndex(of: defaultNext),
                      previousIndex < nextIndex {
                normalized.insert(section, at: previousIndex + 1)
            } else if let defaultNext = nearestPresentDefaultSuccessor(of: section, in: normalized),
                      let insertionIndex = normalized.firstIndex(of: defaultNext) {
                normalized.insert(section, at: insertionIndex)
            } else {
                normalized.append(section)
            }
        }
        return normalized
    }

    private static func nearestPresentDefaultPredecessor(of section: PanelSection, in sections: [PanelSection]) -> PanelSection? {
        guard let defaultIndex = defaultPanelSectionOrder.firstIndex(of: section), defaultIndex > 0 else { return nil }
        return defaultPanelSectionOrder[..<defaultIndex].reversed().first { sections.contains($0) }
    }

    private static func nearestPresentDefaultSuccessor(of section: PanelSection, in sections: [PanelSection]) -> PanelSection? {
        guard let defaultIndex = defaultPanelSectionOrder.firstIndex(of: section),
              defaultIndex < defaultPanelSectionOrder.index(before: defaultPanelSectionOrder.endIndex)
        else { return nil }
        return defaultPanelSectionOrder[defaultPanelSectionOrder.index(after: defaultIndex)...].first { sections.contains($0) }
    }

    static let defaultProxyProbes: [ProxyProbe] = [
        ProxyProbe(name: "Local HTTP 7890", kind: .http, host: "127.0.0.1", port: 7890, enabled: true),
        ProxyProbe(name: "Local SOCKS5 6666", kind: .socks5, host: "127.0.0.1", port: 6666, enabled: true),
    ]

    static let defaultPublicIPProviders = PublicIPProviderCatalog.defaults

    static let defaultGatewayLatencyCaution: Double = 20
    static let defaultGatewayLatencyCritical: Double = 50
    static let defaultExternalLatencyCaution: Double = 250
    static let defaultExternalLatencyCritical: Double = 800
    static let defaultPacketLossCaution: Double = 0.01
    static let defaultPacketLossCritical: Double = 0.05

    static let defaultAppDirectLatencyCaution: Double = 800
    static let defaultAppDirectLatencyCritical: Double = 2_000
    static let defaultAppSystemLatencyCaution: Double = 1_000
    static let defaultAppSystemLatencyCritical: Double = 3_000

    static let defaultApplicationProbes: [ApplicationProbe] = [
        ApplicationProbe(name: "Cloudflare HTTPS", url: "https://www.cloudflare.com/cdn-cgi/trace", route: .system, enabled: true),
        ApplicationProbe(name: "Google 204", url: "https://www.google.com/generate_204", route: .system, enabled: true),
        ApplicationProbe(name: "Direct Cloudflare", url: "https://www.cloudflare.com/cdn-cgi/trace", route: .direct, enabled: false),
    ]

    static let defaultEgressTraceTargets: [EgressTraceTarget] = [
        EgressTraceTarget(
            id: "chatgpt-system-trace",
            name: "ChatGPT",
            url: "https://chatgpt.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: true,
            showInMenuBar: true
        ),
        EgressTraceTarget(
            id: "cloudflare-system-trace",
            name: "Cloudflare",
            url: "https://www.cloudflare.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: false,
            showInMenuBar: false
        ),
        EgressTraceTarget(
            id: "chatgpt-direct-trace",
            name: "ChatGPT Direct",
            url: "https://chatgpt.com/cdn-cgi/trace",
            route: .direct,
            parser: .cloudflareTrace,
            enabled: false,
            showInMenuBar: false
        ),
    ]

    func resetApplicationLatencyThresholds() {
        appDirectLatencyCaution = Self.defaultAppDirectLatencyCaution
        appDirectLatencyCritical = Self.defaultAppDirectLatencyCritical
        appSystemLatencyCaution = Self.defaultAppSystemLatencyCaution
        appSystemLatencyCritical = Self.defaultAppSystemLatencyCritical
    }

    func resetICMPThresholds() {
        gatewayLatencyCaution = Self.defaultGatewayLatencyCaution
        gatewayLatencyCritical = Self.defaultGatewayLatencyCritical
        externalLatencyCaution = Self.defaultExternalLatencyCaution
        externalLatencyCritical = Self.defaultExternalLatencyCritical
        packetLossCaution = Self.defaultPacketLossCaution
        packetLossCritical = Self.defaultPacketLossCritical
    }

    private func migrateWarningThresholdDefaults() {
        let key = "warningThresholdDefaultsVersion"
        guard defaults.integer(forKey: key) < 2 else { return }

        migrateMillisecondsDefault(forKey: "externalLatencyCaution", oldDefault: 100, newDefault: Self.defaultExternalLatencyCaution)
        migrateMillisecondsDefault(forKey: "externalLatencyCritical", oldDefault: 200, newDefault: Self.defaultExternalLatencyCritical)
        migrateMillisecondsDefault(forKey: "appDirectLatencyCaution", oldDefault: 250, newDefault: Self.defaultAppDirectLatencyCaution)
        migrateMillisecondsDefault(forKey: "appDirectLatencyCritical", oldDefault: 750, newDefault: Self.defaultAppDirectLatencyCritical)
        migrateMillisecondsDefault(forKey: "appSystemLatencyCaution", oldDefault: 500, newDefault: Self.defaultAppSystemLatencyCaution)
        migrateMillisecondsDefault(forKey: "appSystemLatencyCritical", oldDefault: 1_500, newDefault: Self.defaultAppSystemLatencyCritical)

        defaults.set(2, forKey: key)
    }

    private func migrateMillisecondsDefault(forKey key: String, oldDefault: Double, newDefault: Double) {
        guard defaults.object(forKey: key) != nil else { return }
        let value = defaults.double(forKey: key)
        if abs(value - oldDefault) < 0.001 {
            defaults.set(newDefault, forKey: key)
        }
    }

    private func boundedMilliseconds(forKey key: String, defaultValue: Double) -> Double {
        let value = defaults.double(forKey: key).nonZero ?? defaultValue
        return min(max(value, 1), 10_000)
    }

    private func setBoundedMilliseconds(_ value: Double, forKey key: String) {
        defaults.set(min(max(value, 1), 10_000), forKey: key)
    }

    private func boundedRatio(forKey key: String, defaultValue: Double) -> Double {
        let value = defaults.double(forKey: key).nonZero ?? defaultValue
        return min(max(value, 0.01), 1)
    }

    private func setBoundedRatio(_ value: Double, forKey key: String) {
        defaults.set(min(max(value, 0.01), 1), forKey: key)
    }
}

struct PingHost: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var address: String
    var label: String
    var enabled: Bool

    init(id: String? = nil, address: String, label: String, enabled: Bool) {
        self.id = id ?? address
        self.address = address
        self.label = label
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? address
        label = try container.decode(String.self, forKey: .label)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }
}

struct ProxyProbe: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var kind: ProxyProbeKind
    var host: String
    var port: Int
    var enabled: Bool
    var ipFamily: IPProbeFamily

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: ProxyProbeKind,
        host: String,
        port: Int,
        enabled: Bool,
        ipFamily: IPProbeFamily = .automatic
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.enabled = enabled
        self.ipFamily = ipFamily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ProxyProbeKind.self, forKey: .kind)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        ipFamily = try container.decodeIfPresent(IPProbeFamily.self, forKey: .ipFamily) ?? .automatic
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? endpoint : trimmed
    }

    var endpoint: String {
        "\(kind.label) \(host):\(port)"
    }

    var routeDetail: String {
        "\(endpoint) · \(ipFamily.label)"
    }
}

enum ProxyProbeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case socks5

    var id: String { rawValue }

    var label: String {
        switch self {
        case .http: return "HTTP(S)"
        case .socks5: return "SOCKS5"
        }
    }
}

enum IPProbeFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case ipv4
    case ipv6

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Auto"
        case .ipv4: return "IPv4"
        case .ipv6: return "IPv6"
        }
    }

    var detailLabel: String {
        switch self {
        case .automatic: return "dual-stack"
        case .ipv4: return "IPv4 only"
        case .ipv6: return "IPv6 only"
        }
    }
}

enum PublicIPResponseParser: String, Codable, CaseIterable, Identifiable, Sendable {
    case jsonIP
    case jsonOrigin
    case plainText
    case cloudflareMeta
    case cloudflareTrace
    case ipinfoCore
    case ipinfoLegacy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jsonIP: return "JSON ip"
        case .jsonOrigin: return "JSON origin"
        case .plainText: return "Plain text"
        case .cloudflareMeta: return "Cloudflare meta"
        case .cloudflareTrace: return "Cloudflare trace"
        case .ipinfoCore: return "IPinfo core"
        case .ipinfoLegacy: return "IPinfo legacy"
        }
    }
}

struct PublicIPProvider: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var url: String
    var family: IPProbeFamily
    var parser: PublicIPResponseParser
    var enabled: Bool
    var diagnostic: Bool
    var requiresIPInfoToken: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        family: IPProbeFamily,
        parser: PublicIPResponseParser,
        enabled: Bool,
        diagnostic: Bool = false,
        requiresIPInfoToken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.family = family
        self.parser = parser
        self.enabled = enabled
        self.diagnostic = diagnostic
        self.requiresIPInfoToken = requiresIPInfoToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        family = try container.decode(IPProbeFamily.self, forKey: .family)
        parser = try container.decode(PublicIPResponseParser.self, forKey: .parser)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        diagnostic = try container.decodeIfPresent(Bool.self, forKey: .diagnostic) ?? false
        requiresIPInfoToken = try container.decodeIfPresent(Bool.self, forKey: .requiresIPInfoToken) ?? false
    }
}

enum ApplicationProbeRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .direct: return "Direct"
        }
    }

    var detail: String {
        switch self {
        case .system: return "macOS proxy settings"
        case .direct: return "URL proxy disabled"
        }
    }
}

struct ApplicationProbe: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var url: String
    var route: ApplicationProbeRoute
    var enabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        route: ApplicationProbeRoute,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.route = route
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        route = try container.decode(ApplicationProbeRoute.self, forKey: .route)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }
}

struct ApplicationProbeResult: Identifiable, Equatable, Sendable {
    var id: String { probe.id }
    let probe: ApplicationProbe
    let durationMs: Double?
    let phaseMetrics: ApplicationProbePhaseMetrics?
    let statusCode: Int?
    let error: String?
    let date: Date

    var isHealthy: Bool {
        guard let statusCode else { return false }
        return (200...399).contains(statusCode)
    }
}

struct ApplicationProbePhaseMetrics: Codable, Equatable, Sendable {
    let dnsMs: Double?
    let connectMs: Double?
    let tlsMs: Double?
    let requestMs: Double?
    let responseMs: Double?
    let ttfbMs: Double?
    let protocolName: String?
    let isProxyConnection: Bool?
    let isReusedConnection: Bool?

    init(
        dnsMs: Double? = nil,
        connectMs: Double? = nil,
        tlsMs: Double? = nil,
        requestMs: Double? = nil,
        responseMs: Double? = nil,
        ttfbMs: Double? = nil,
        protocolName: String? = nil,
        isProxyConnection: Bool? = nil,
        isReusedConnection: Bool? = nil
    ) {
        self.dnsMs = dnsMs
        self.connectMs = connectMs
        self.tlsMs = tlsMs
        self.requestMs = requestMs
        self.responseMs = responseMs
        self.ttfbMs = ttfbMs
        self.protocolName = protocolName
        self.isProxyConnection = isProxyConnection
        self.isReusedConnection = isReusedConnection
    }
}

enum EgressTraceParser: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloudflareTrace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloudflareTrace: return "Cloudflare trace"
        }
    }
}

struct EgressTraceTarget: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var url: String
    var route: ApplicationProbeRoute
    var parser: EgressTraceParser
    var enabled: Bool
    var showInMenuBar: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        route: ApplicationProbeRoute,
        parser: EgressTraceParser = .cloudflareTrace,
        enabled: Bool,
        showInMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.route = route
        self.parser = parser
        self.enabled = enabled
        self.showInMenuBar = showInMenuBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        route = try container.decodeIfPresent(ApplicationProbeRoute.self, forKey: .route) ?? .system
        parser = try container.decodeIfPresent(EgressTraceParser.self, forKey: .parser) ?? .cloudflareTrace
        enabled = try container.decode(Bool.self, forKey: .enabled)
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? URL(string: url)?.host ?? url : trimmed
    }
}

struct EgressTraceResult: Identifiable, Equatable, Sendable {
    var id: String { target.id }
    let target: EgressTraceTarget
    let endpoint: PublicEndpointInfo?
    let durationMs: Double?
    let statusCode: Int?
    let error: String?
    let date: Date

    var isHealthy: Bool {
        guard let statusCode else { return endpoint != nil }
        return endpoint != nil && (200...399).contains(statusCode)
    }
}

struct ProxyProbeResult: Identifiable, Equatable, Sendable {
    var id: String { probe.id }
    let probe: ProxyProbe
    let endpoint: PublicEndpointInfo?
    let evidence: PublicIPEvidence?

    init(probe: ProxyProbe, endpoint: PublicEndpointInfo?, evidence: PublicIPEvidence? = nil) {
        self.probe = probe
        self.endpoint = endpoint
        self.evidence = evidence
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case stacked
    case compact
    case detailed
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stacked:  return "Stacked"
        case .compact:  return "Compact"
        case .detailed: return "Detailed"
        case .iconOnly: return "Icon Only"
        }
    }
}

enum MenuBarContentMode: String, CaseIterable, Identifiable, Sendable {
    case speed
    case egress
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed:  return "Speed"
        case .egress: return "Egress IP"
        case .hybrid: return "Speed + Egress"
        }
    }
}

enum PanelSection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case latency
    case metricRollups
    case throughput
    case trafficUsage
    case egress
    case wifi
    case processes
    case speedTest
    case speedHistory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latency: return "Latency"
        case .metricRollups: return "Metric Rollups"
        case .throughput: return "Live Throughput"
        case .trafficUsage: return "Traffic Usage"
        case .egress: return "Egress"
        case .wifi: return "Wi-Fi"
        case .processes: return "Processes"
        case .speedTest: return "Speed Test"
        case .speedHistory: return "Speed History"
        }
    }

    var detail: String {
        switch self {
        case .latency: return "ICMP path health"
        case .metricRollups: return "time-window evidence"
        case .throughput: return "current down/up rate"
        case .trafficUsage: return "accumulated down/up"
        case .egress: return "proxy and public IP"
        case .wifi: return "radio and interface"
        case .processes: return "top app traffic"
        case .speedTest: return "on-demand test"
        case .speedHistory: return "recent test results"
        }
    }

    var systemImage: String {
        switch self {
        case .latency: return "waveform.path.ecg"
        case .metricRollups: return "chart.xyaxis.line"
        case .throughput: return "arrow.up.arrow.down"
        case .trafficUsage: return "chart.bar.xaxis"
        case .egress: return "globe"
        case .wifi: return "wifi"
        case .processes: return "list.bullet.rectangle"
        case .speedTest: return "speedometer"
        case .speedHistory: return "clock.arrow.circlepath"
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

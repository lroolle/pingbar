import Foundation

final class AppConfig {
    static let shared = AppConfig()

    private let defaults = UserDefaults.standard

    var pingHosts: [PingHost] {
        get {
            guard let data = defaults.data(forKey: "pingHosts_v2"),
                  let hosts = try? JSONDecoder().decode([PingHost].self, from: data)
            else { return Self.defaultPingHosts }
            return hosts
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
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

    static let defaultPingHosts: [PingHost] = [
        PingHost(address: "1.1.1.1", label: "Cloudflare", enabled: true),
        PingHost(address: "8.8.8.8", label: "Google", enabled: true),
        PingHost(address: "223.5.5.5", label: "Alibaba", enabled: false),
        PingHost(address: "119.29.29.29", label: "Tencent", enabled: false),
    ]

    static let defaultProxyProbes: [ProxyProbe] = [
        ProxyProbe(name: "Local HTTP 7890", kind: .http, host: "127.0.0.1", port: 7890, enabled: true),
        ProxyProbe(name: "Local SOCKS5 6666", kind: .socks5, host: "127.0.0.1", port: 6666, enabled: true),
    ]

    static let defaultPublicIPProviders = PublicIPProviderCatalog.defaults

    static let defaultApplicationProbes: [ApplicationProbe] = [
        ApplicationProbe(name: "Cloudflare HTTPS", url: "https://www.cloudflare.com/cdn-cgi/trace", route: .system, enabled: true),
        ApplicationProbe(name: "Google 204", url: "https://www.google.com/generate_204", route: .system, enabled: true),
        ApplicationProbe(name: "Direct Cloudflare", url: "https://www.cloudflare.com/cdn-cgi/trace", route: .direct, enabled: false),
    ]
}

struct PingHost: Codable, Identifiable, Equatable, Sendable {
    var id: String { address }
    var address: String
    var label: String
    var enabled: Bool
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
    var id: String = UUID().uuidString
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
    var id: String = UUID().uuidString
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
}

struct ApplicationProbeResult: Identifiable, Equatable, Sendable {
    var id: String { probe.id }
    let probe: ApplicationProbe
    let durationMs: Double?
    let statusCode: Int?
    let error: String?
    let date: Date

    var isHealthy: Bool {
        guard let statusCode else { return false }
        return (200...399).contains(statusCode)
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

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

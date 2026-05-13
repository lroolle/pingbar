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

    var showUploadInMenuBar: Bool {
        get { defaults.object(forKey: "showUploadInMenuBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showUploadInMenuBar") }
    }

    var showHealthDot: Bool {
        get { defaults.object(forKey: "showHealthDot") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showHealthDot") }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .compact }
        set { defaults.set(newValue.rawValue, forKey: "menuBarStyle") }
    }

    static let defaultPingHosts: [PingHost] = [
        PingHost(address: "1.1.1.1", label: "Cloudflare", enabled: true),
        PingHost(address: "8.8.8.8", label: "Google", enabled: true),
        PingHost(address: "223.5.5.5", label: "Alibaba", enabled: false),
        PingHost(address: "119.29.29.29", label: "Tencent", enabled: false),
    ]
}

struct PingHost: Codable, Identifiable, Equatable {
    var id: String { address }
    var address: String
    var label: String
    var enabled: Bool
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case compact
    case detailed
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact:  return "Compact"
        case .detailed: return "Detailed"
        case .iconOnly: return "Icon Only"
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

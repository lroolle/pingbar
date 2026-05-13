import SystemConfiguration

enum PrimaryInterface {
    static func name() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "PingBar" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    static func gatewayIP() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "PingBar" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["Router"] as? String
    }
}

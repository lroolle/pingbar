import Foundation
import SystemConfiguration

enum PrimaryInterface {
    static func name() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "PingBar" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    static func displayLabel(for name: String?) -> String? {
        guard let name else { return nil }

        for item in SCNetworkInterfaceCopyAll() as NSArray {
            let interface = item as! SCNetworkInterface
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                  bsdName == name
            else { continue }

            guard let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
                  !displayName.isEmpty,
                  displayName != name
            else { return name }

            return "\(displayName) (\(name))"
        }

        return name
    }

    static func gatewayIP() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "PingBar" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["Router"] as? String
    }
}

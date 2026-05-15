import Foundation

struct PublicEndpointInfo: Codable, Equatable, Sendable {
    var ip: String
    var city: String? = nil
    var region: String? = nil
    var country: String? = nil
    var asn: Int? = nil
    var organization: String? = nil
    var colo: String? = nil
    var warp: String? = nil
    var gateway: String? = nil
    var httpProtocol: String? = nil
    var traceLocation: String? = nil
    var source: String? = nil

    var locationLabel: String? {
        let parts = [city, region, countryCode ?? country].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var networkLabel: String? {
        if let asn, let organization, !organization.isEmpty {
            return "AS\(asn) \(organization)"
        }
        if let organization, !organization.isEmpty {
            return organization
        }
        if let asn {
            return "AS\(asn)"
        }
        return nil
    }

    var warpLabel: String? {
        guard let warp, !warp.isEmpty else { return nil }
        switch warp {
        case "on": return "WARP on"
        case "plus": return "WARP+"
        case "off": return "WARP off"
        default: return "WARP \(warp)"
        }
    }

    var gatewayLabel: String? {
        guard let gateway, !gateway.isEmpty, gateway != "off" else { return nil }
        return "Gateway \(gateway)"
    }

    var countryCode: String? {
        for value in [country, traceLocation] {
            guard let code = Self.normalizedCountryCode(value) else { continue }
            return code
        }
        return nil
    }

    var flagEmoji: String? {
        guard let code = countryCode else { return nil }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            UnicodeScalar(base + scalar.value)
        }
        guard scalars.count == 2 else { return nil }
        return scalars.map(String.init).joined()
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2,
              code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) })
        else { return nil }
        return code
    }
}

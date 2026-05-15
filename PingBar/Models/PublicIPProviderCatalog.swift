import Foundation

enum PublicIPProviderCatalog {
    static var defaults: [PublicIPProvider] {
        BuiltIn.allCases.map(\.provider)
    }

    static func normalized(_ providers: [PublicIPProvider]) -> [PublicIPProvider] {
        providers.map(normalized)
    }

    static func normalized(_ provider: PublicIPProvider) -> PublicIPProvider {
        guard let endpoint = BuiltIn.ipinfoEndpoint(for: provider) else { return provider }
        var copy = provider
        copy.url = endpoint.legacyURL
        copy.parser = .ipinfoLegacy
        copy.requiresIPInfoToken = true
        return copy
    }
}

private extension PublicIPProviderCatalog {
    enum BuiltIn: String, CaseIterable {
        case ipinfoAuto = "ipinfo-auto"
        case ipinfoIPv4 = "ipinfo-ipv4"
        case ipinfoIPv6 = "ipinfo-ipv6"
        case ipifyAuto = "ipify-auto"
        case ipifyIPv4 = "ipify-ipv4"
        case ipifyIPv6 = "ipify-ipv6"
        case awsIPv4 = "aws-ipv4"
        case cloudflareMeta = "cloudflare-meta"
        case cloudflareTrace = "cloudflare-trace"

        var provider: PublicIPProvider {
            switch self {
            case .ipinfoAuto:
                return provider(
                    name: "IPinfo Auto",
                    url: IPinfoEndpoint.auto.legacyURL,
                    family: .automatic,
                    parser: .ipinfoLegacy,
                    requiresIPInfoToken: true
                )
            case .ipinfoIPv4:
                return provider(
                    name: "IPinfo IPv4",
                    url: IPinfoEndpoint.auto.legacyURL,
                    family: .ipv4,
                    parser: .ipinfoLegacy,
                    requiresIPInfoToken: true
                )
            case .ipinfoIPv6:
                return provider(
                    name: "IPinfo IPv6",
                    url: IPinfoEndpoint.ipv6.legacyURL,
                    family: .ipv6,
                    parser: .ipinfoLegacy,
                    requiresIPInfoToken: true
                )
            case .ipifyAuto:
                return provider(
                    name: "ipify Auto",
                    url: "https://api64.ipify.org?format=json",
                    family: .automatic,
                    parser: .jsonIP
                )
            case .ipifyIPv4:
                return provider(
                    name: "ipify IPv4",
                    url: "https://api.ipify.org?format=json",
                    family: .ipv4,
                    parser: .jsonIP
                )
            case .ipifyIPv6:
                return provider(
                    name: "ipify IPv6",
                    url: "https://api6.ipify.org?format=json",
                    family: .ipv6,
                    parser: .jsonIP
                )
            case .awsIPv4:
                return provider(
                    name: "AWS IPv4",
                    url: "https://checkip.amazonaws.com",
                    family: .ipv4,
                    parser: .plainText
                )
            case .cloudflareMeta:
                return provider(
                    name: "Cloudflare Meta",
                    url: "https://speed.cloudflare.com/meta",
                    family: .automatic,
                    parser: .cloudflareMeta,
                    diagnostic: true
                )
            case .cloudflareTrace:
                return provider(
                    name: "Cloudflare Trace",
                    url: "https://www.cloudflare.com/cdn-cgi/trace",
                    family: .automatic,
                    parser: .cloudflareTrace,
                    diagnostic: true
                )
            }
        }

        private func provider(
            name: String,
            url: String,
            family: IPProbeFamily,
            parser: PublicIPResponseParser,
            diagnostic: Bool = false,
            requiresIPInfoToken: Bool = false
        ) -> PublicIPProvider {
            PublicIPProvider(
                id: rawValue,
                name: name,
                url: url,
                family: family,
                parser: parser,
                enabled: true,
                diagnostic: diagnostic,
                requiresIPInfoToken: requiresIPInfoToken
            )
        }

        static func ipinfoEndpoint(for provider: PublicIPProvider) -> IPinfoEndpoint? {
            guard let builtIn = Self.allCases.first(where: { candidate in
                candidate.rawValue == provider.id || candidate.provider.name == provider.name
            }) else { return nil }

            switch builtIn {
            case .ipinfoAuto, .ipinfoIPv4:
                return IPinfoEndpoint(url: provider.url)
            case .ipinfoIPv6:
                return IPinfoEndpoint(url: provider.url)
            case .ipifyAuto, .ipifyIPv4, .ipifyIPv6, .awsIPv4, .cloudflareMeta, .cloudflareTrace:
                return nil
            }
        }
    }

    enum IPinfoEndpoint {
        case auto
        case ipv6

        init?(url: String) {
            switch url.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "https://api.ipinfo.io/lookup/me?token={ipinfoToken}",
                 "https://v4.api.ipinfo.io/lookup/me?token={ipinfoToken}",
                 "https://ipinfo.io/json?token={ipinfoToken}",
                 "https://ipinfo.io/?token={ipinfoToken}":
                self = .auto
            case "https://v6.api.ipinfo.io/lookup/me?token={ipinfoToken}",
                 "https://v6.ipinfo.io/json?token={ipinfoToken}",
                 "https://v6.ipinfo.io/?token={ipinfoToken}":
                self = .ipv6
            default:
                return nil
            }
        }

        var legacyURL: String {
            switch self {
            case .auto:
                return "https://ipinfo.io/json?token={ipinfoToken}"
            case .ipv6:
                return "https://v6.ipinfo.io/json?token={ipinfoToken}"
            }
        }
    }
}

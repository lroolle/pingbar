import Foundation
import CFNetwork

struct PublicIPProbeContext: Sendable {
    let providers: [PublicIPProvider]
    let ipInfoToken: String

    init(providers: [PublicIPProvider], ipInfoToken: String) {
        self.providers = providers
        self.ipInfoToken = ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class PublicIPReader: Sendable {
    private struct IPResponse: Codable {
        let ip: String
    }

    private struct CloudflareMetaResponse: Codable {
        let clientIp: String
        let city: String?
        let country: String?
        let asn: Int?
        let asOrganization: String?
        let colo: ColoResponse?
    }

    private struct ColoResponse: Codable {
        let iata: String?
    }

    private struct IPInfoResponse: Codable {
        let ip: String?
        let city: String?
        let region: String?
        let country: String?
        let org: String?
    }

    private struct IPInfoCoreResponse: Codable {
        let ip: String?
        let geo: IPInfoCoreGeo?
        let autonomousSystem: IPInfoCoreAS?

        enum CodingKeys: String, CodingKey {
            case ip
            case geo
            case autonomousSystem = "as"
        }
    }

    private struct IPInfoCoreGeo: Codable {
        let city: String?
        let region: String?
        let countryCode: String?

        enum CodingKeys: String, CodingKey {
            case city
            case region
            case countryCode = "country_code"
        }
    }

    private struct IPInfoCoreAS: Codable {
        let asn: String?
        let name: String?
    }

    private struct CloudflareTrace {
        let fields: [String: String]

        var ip: String? { fields["ip"] }
        var colo: String? { fields["colo"] }
        var location: String? { fields["loc"] }
        var warp: String? { fields["warp"] }
        var gateway: String? { fields["gateway"] }
        var httpProtocol: String? { fields["http"] }
    }

    private static func makeNoURLProxySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
        ]
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }

    private static func makeSystemPathSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }

    private static func makeProxySession(_ probe: ProxyProbe) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5

        switch probe.kind {
        case .http:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: probe.host,
                kCFNetworkProxiesHTTPPort as String: probe.port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: probe.host,
                kCFNetworkProxiesHTTPSPort as String: probe.port,
                kCFNetworkProxiesSOCKSEnable as String: 0,
                kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
            ]
        case .socks5:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 0,
                kCFNetworkProxiesHTTPSEnable as String: 0,
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: probe.host,
                kCFNetworkProxiesSOCKSPort as String: probe.port,
                kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0,
            ]
        }

        return URLSession(configuration: config)
    }

    func fetchDirectEvidence(family: IPProbeFamily, context: PublicIPProbeContext) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeNoURLProxySession(), family: family, context: context)
    }

    func fetchProxyEvidence(family: IPProbeFamily, context: PublicIPProbeContext) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeSystemPathSession(), family: family, context: context)
    }

    func fetchEvidence(via probe: ProxyProbe, context: PublicIPProbeContext) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeProxySession(probe), family: probe.ipFamily, context: context)
    }

    private func fetchEvidence(session: URLSession, family: IPProbeFamily, context: PublicIPProbeContext) async -> PublicIPEvidence {
        defer { session.finishTasksAndInvalidate() }

        let providers = context.providers.filter { provider in
            provider.enabled && Self.provider(provider, matches: family)
        }
        return PublicIPEvidence(
            probes: await fetchProviderResults(
                session: session,
                providers: providers,
                ipInfoToken: context.ipInfoToken
            )
        )
    }

    private static func parseASN(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.uppercased().hasPrefix("AS") ? String(value.dropFirst(2)) : value
        return Int(digits)
    }

    private static func parseIPInfoOrganization(_ value: String?) -> (asn: Int?, organization: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, first.hasPrefix("AS") else {
            return (nil, value)
        }

        let asnText = String(first.dropFirst(2))
        let organization = parts.count > 1 ? parts[1] : nil
        return (Int(asnText), organization)
    }

    private static func provider(_ provider: PublicIPProvider, matches family: IPProbeFamily) -> Bool {
        if provider.diagnostic {
            return provider.family == .automatic || provider.family == family
        }
        if family == .automatic {
            return provider.family == .automatic
        }
        return provider.family == family
    }

    private func fetchProviderResults(
        session: URLSession,
        providers: [PublicIPProvider],
        ipInfoToken: String
    ) async -> [PublicIPProbeResult] {
        var results: [PublicIPProbeResult] = []
        for provider in providers {
            if let result = await Self.fetchProvider(
                session: session,
                provider: provider,
                ipInfoToken: ipInfoToken
            ) {
                results.append(result)
            }
        }
        return results
    }

    private static func fetchProvider(
        session: URLSession,
        provider: PublicIPProvider,
        ipInfoToken: String
    ) async -> PublicIPProbeResult? {
        if provider.requiresIPInfoToken, ipInfoToken.isEmpty {
            return nil
        }

        let encodedToken = ipInfoToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ipInfoToken
        let urlString = provider.url.replacingOccurrences(of: "{ipinfoToken}", with: encodedToken)
        guard let url = URL(string: urlString) else {
            return PublicIPProbeResult(source: provider.name, endpoint: nil, diagnostic: provider.diagnostic, providerID: provider.id)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if provider.parser == .cloudflareMeta {
            request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return PublicIPProbeResult(source: provider.name, endpoint: nil, diagnostic: provider.diagnostic, providerID: provider.id)
            }

            let endpoint = Self.parseProviderResponse(data, provider: provider)
            return PublicIPProbeResult(source: provider.name, endpoint: endpoint, diagnostic: provider.diagnostic, providerID: provider.id)
        } catch {
            return PublicIPProbeResult(source: provider.name, endpoint: nil, diagnostic: provider.diagnostic, providerID: provider.id)
        }
    }

    static func parseProviderResponse(_ data: Data, provider: PublicIPProvider) -> PublicEndpointInfo? {
        switch provider.parser {
        case .jsonIP:
            guard let resp = try? JSONDecoder().decode(IPResponse.self, from: data) else { return nil }
            return PublicEndpointInfo(ip: resp.ip, source: provider.name)

        case .jsonOrigin:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let origin = json["origin"] as? String,
                  let ip = origin.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
                  !ip.isEmpty
            else { return nil }
            return PublicEndpointInfo(ip: ip, source: provider.name)

        case .plainText:
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count < 80,
                  text.contains(".") || text.contains(":")
            else { return nil }
            return PublicEndpointInfo(ip: text, source: provider.name)

        case .cloudflareMeta:
            guard let meta = try? JSONDecoder().decode(CloudflareMetaResponse.self, from: data) else { return nil }
            return PublicEndpointInfo(
                ip: meta.clientIp,
                city: meta.city,
                country: meta.country,
                asn: meta.asn,
                organization: meta.asOrganization,
                colo: meta.colo?.iata,
                source: provider.name
            )

        case .cloudflareTrace:
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let fields = text
                .components(separatedBy: .newlines)
                .reduce(into: [String: String]()) { result, line in
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return }
                    result[key] = value
            }
            let trace = CloudflareTrace(fields: fields)
            guard let ip = trace.ip, !ip.isEmpty else { return nil }
            return PublicEndpointInfo(
                ip: ip,
                country: trace.location,
                colo: trace.colo,
                warp: trace.warp,
                gateway: trace.gateway,
                httpProtocol: trace.httpProtocol,
                traceLocation: trace.location,
                source: provider.name
            )

        case .ipinfoCore:
            guard let info = try? JSONDecoder().decode(IPInfoCoreResponse.self, from: data),
                  let ip = info.ip,
                  !ip.isEmpty
            else { return nil }
            return PublicEndpointInfo(
                ip: ip,
                city: info.geo?.city,
                region: info.geo?.region,
                country: info.geo?.countryCode,
                asn: parseASN(info.autonomousSystem?.asn),
                organization: info.autonomousSystem?.name,
                source: provider.name
            )

        case .ipinfoLegacy:
            guard let info = try? JSONDecoder().decode(IPInfoResponse.self, from: data),
                  let ip = info.ip,
                  !ip.isEmpty
            else { return nil }
            let parsedOrg = parseIPInfoOrganization(info.org)
            return PublicEndpointInfo(
                ip: ip,
                city: info.city,
                region: info.region,
                country: info.country,
                asn: parsedOrg.asn,
                organization: parsedOrg.organization,
                source: provider.name
            )
        }
    }

}

import Foundation

final class PublicIPReader {
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

    private static func rawIPAPIs(for family: IPProbeFamily) -> [(source: String, url: String)] {
        switch family {
        case .automatic:
            return [
                ("ipify", "https://api64.ipify.org?format=json"),
            ]
        case .ipv4:
            return [
                ("ipify4", "https://api.ipify.org?format=json"),
                ("aws", "https://checkip.amazonaws.com"),
            ]
        case .ipv6:
            return [
                ("ipify6", "https://api6.ipify.org?format=json"),
            ]
        }
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

    func fetchDirectIP() async -> String? {
        await fetchEndpoint(session: Self.makeNoURLProxySession(), family: .automatic)?.ip
    }

    func fetchProxyIP() async -> String? {
        await fetchEndpoint(session: Self.makeSystemPathSession(), family: .automatic)?.ip
    }

    func fetchDirectEndpoint() async -> PublicEndpointInfo? {
        await fetchEndpoint(session: Self.makeNoURLProxySession(), family: .automatic)
    }

    func fetchProxyEndpoint() async -> PublicEndpointInfo? {
        await fetchEndpoint(session: Self.makeSystemPathSession(), family: .automatic)
    }

    func fetchEndpoint(via probe: ProxyProbe) async -> PublicEndpointInfo? {
        await fetchEndpoint(session: Self.makeProxySession(probe), family: probe.ipFamily)
    }

    func fetchDirectEvidence(family: IPProbeFamily = .automatic) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeNoURLProxySession(), family: family)
    }

    func fetchProxyEvidence(family: IPProbeFamily = .automatic) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeSystemPathSession(), family: family)
    }

    func fetchEvidence(via probe: ProxyProbe) async -> PublicIPEvidence {
        await fetchEvidence(session: Self.makeProxySession(probe), family: probe.ipFamily)
    }

    private func fetchEndpoint(session: URLSession, family: IPProbeFamily) async -> PublicEndpointInfo? {
        await fetchEvidence(session: session, family: family).primaryEndpoint
    }

    private func fetchEvidence(session: URLSession, family: IPProbeFamily) async -> PublicIPEvidence {
        let providers = AppConfig.shared.publicIPProviders.filter { provider in
            provider.enabled && Self.provider(provider, matches: family)
        }
        return PublicIPEvidence(probes: await fetchProviderResults(session: session, providers: providers))
    }

    private func mergedCloudflareEndpoint(
        metaInfo: PublicEndpointInfo?,
        traceInfo: CloudflareTrace?
    ) -> PublicEndpointInfo? {
        if var info = metaInfo {
            info.warp = traceInfo?.warp
            info.gateway = traceInfo?.gateway
            info.httpProtocol = traceInfo?.httpProtocol
            info.traceLocation = traceInfo?.location
            if info.colo == nil { info.colo = traceInfo?.colo }
            info.source = "cloudflare"
            return info
        }

        if let traceInfo, let ip = traceInfo.ip {
            return PublicEndpointInfo(
                ip: ip,
                country: traceInfo.location,
                colo: traceInfo.colo,
                warp: traceInfo.warp,
                gateway: traceInfo.gateway,
                httpProtocol: traceInfo.httpProtocol,
                traceLocation: traceInfo.location,
                source: "cloudflare"
            )
        }

        return nil
    }

    private func parseASN(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.uppercased().hasPrefix("AS") ? String(value.dropFirst(2)) : value
        return Int(digits)
    }

    private func parseIPInfoOrganization(_ value: String?) -> (asn: Int?, organization: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, first.hasPrefix("AS") else {
            return (nil, value)
        }

        let asnText = String(first.dropFirst(2))
        let organization = parts.count > 1 ? parts[1] : nil
        return (Int(asnText), organization)
    }

    private func fetchCloudflareMeta(session: URLSession) async -> PublicEndpointInfo? {
        guard let url = URL(string: "https://speed.cloudflare.com/meta") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let meta = try JSONDecoder().decode(CloudflareMetaResponse.self, from: data)
            return PublicEndpointInfo(
                ip: meta.clientIp,
                city: meta.city,
                country: meta.country,
                asn: meta.asn,
                organization: meta.asOrganization,
                colo: meta.colo?.iata
            )
        } catch {
            return nil
        }
    }

    private func fetchCloudflareTrace(session: URLSession) async -> CloudflareTrace? {
        guard let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let fields = text
                .split(separator: "\n")
                .reduce(into: [String: String]()) { result, line in
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return }
                    result[String(parts[0])] = String(parts[1])
                }
            return CloudflareTrace(fields: fields)
        } catch {
            return nil
        }
    }

    private func fetchRawIPs(session: URLSession, family: IPProbeFamily) async -> [PublicIPProbeResult] {
        var probes: [PublicIPProbeResult] = []
        for api in Self.rawIPAPIs(for: family) {
            let endpoint = await fetchRawIP(session: session, source: api.source, urlString: api.url)
            probes.append(PublicIPProbeResult(source: api.source, endpoint: endpoint, diagnostic: false))
        }
        return probes
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

    private func fetchProviderResults(session: URLSession, providers: [PublicIPProvider]) async -> [PublicIPProbeResult] {
        await withTaskGroup(of: PublicIPProbeResult?.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    await self?.fetchProvider(session: session, provider: provider)
                }
            }

            var results: [PublicIPProbeResult] = []
            for await result in group {
                if let result { results.append(result) }
            }

            let order = Dictionary(uniqueKeysWithValues: providers.enumerated().map { ($0.element.id, $0.offset) })
            return results.sorted {
                (order[$0.providerID ?? ""] ?? Int.max) < (order[$1.providerID ?? ""] ?? Int.max)
            }
        }
    }

    private func fetchProvider(session: URLSession, provider: PublicIPProvider) async -> PublicIPProbeResult? {
        let token = AppConfig.shared.ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.requiresIPInfoToken, token.isEmpty {
            return nil
        }

        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
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

            let endpoint = parseProviderResponse(data, provider: provider)
            return PublicIPProbeResult(source: provider.name, endpoint: endpoint, diagnostic: provider.diagnostic, providerID: provider.id)
        } catch {
            return PublicIPProbeResult(source: provider.name, endpoint: nil, diagnostic: provider.diagnostic, providerID: provider.id)
        }
    }

    private func parseProviderResponse(_ data: Data, provider: PublicIPProvider) -> PublicEndpointInfo? {
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
                .split(separator: "\n")
                .reduce(into: [String: String]()) { result, line in
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { return }
                    result[String(parts[0])] = String(parts[1])
                }
            let trace = CloudflareTrace(fields: fields)
            guard let ip = trace.ip else { return nil }
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

    private func fetchRawIP(session: URLSession, source: String, urlString: String) async -> PublicEndpointInfo? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            if let resp = try? JSONDecoder().decode(IPResponse.self, from: data) {
                return PublicEndpointInfo(ip: resp.ip, source: source)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let origin = json["origin"] as? String,
               let ip = origin.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) {
                return PublicEndpointInfo(ip: ip, source: source)
            }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               text.count < 50, text.contains(".") || text.contains(":") {
                return PublicEndpointInfo(ip: text, source: source)
            }
        } catch {
            return nil
        }

        return nil
    }
}

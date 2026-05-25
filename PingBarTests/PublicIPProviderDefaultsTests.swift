import XCTest

final class PublicIPProviderDefaultsTests: XCTestCase {
    func testDefaultProvidersHaveStableBuiltInIDs() {
        let ids = AppConfig.defaultPublicIPProviders.map(\.id)

        XCTAssertEqual(ids, [
            "ipinfo-auto",
            "ipinfo-ipv4",
            "ipinfo-ipv6",
            "ipify-auto",
            "ipify-ipv4",
            "ipify-ipv6",
            "aws-ipv4",
            "cloudflare-meta",
            "cloudflare-trace",
        ])
    }

    func testDecodesOlderPublicIPProviderWithoutIDOrOptionalFlags() throws {
        let data = Data("""
        {
          "name": "Trace",
          "url": "https://www.cloudflare.com/cdn-cgi/trace",
          "family": "automatic",
          "parser": "cloudflareTrace",
          "enabled": true
        }
        """.utf8)

        let provider = try JSONDecoder().decode(PublicIPProvider.self, from: data)

        XCTAssertFalse(provider.id.isEmpty)
        XCTAssertEqual(provider.name, "Trace")
        XCTAssertEqual(provider.parser, .cloudflareTrace)
        XCTAssertFalse(provider.diagnostic)
        XCTAssertFalse(provider.requiresIPInfoToken)
    }

    func testDecodesOlderApplicationProbeWithoutID() throws {
        let data = Data("""
        {
          "name": "Cloudflare",
          "url": "https://www.cloudflare.com/cdn-cgi/trace",
          "route": "system",
          "enabled": true
        }
        """.utf8)

        let probe = try JSONDecoder().decode(ApplicationProbe.self, from: data)

        XCTAssertFalse(probe.id.isEmpty)
        XCTAssertEqual(probe.name, "Cloudflare")
        XCTAssertEqual(probe.url, "https://www.cloudflare.com/cdn-cgi/trace")
        XCTAssertEqual(probe.route, .system)
        XCTAssertTrue(probe.enabled)
    }

    func testDefaultIPinfoProvidersUseLegacyJSONEndpoints() throws {
        let providers = AppConfig.defaultPublicIPProviders
            .filter { $0.name.hasPrefix("IPinfo") }
            .reduce(into: [String: PublicIPProvider]()) { providers, provider in
                providers[provider.name] = provider
            }
        let auto = try XCTUnwrap(providers["IPinfo Auto"])
        let ipv4 = try XCTUnwrap(providers["IPinfo IPv4"])
        let ipv6 = try XCTUnwrap(providers["IPinfo IPv6"])

        XCTAssertEqual(auto.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(ipv4.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(ipv6.url, "https://v6.ipinfo.io/json?token={ipinfoToken}")
        XCTAssertTrue(providers.values.allSatisfy { $0.parser == .ipinfoLegacy })
        XCTAssertTrue(providers.values.allSatisfy(\.requiresIPInfoToken))
    }

    func testMigratesPersistedCoreIPinfoProvidersToLegacyJSONEndpoints() throws {
        let providers = [
            PublicIPProvider(
                name: "IPinfo Auto",
                url: "https://api.ipinfo.io/lookup/me?token={ipinfoToken}",
                family: .automatic,
                parser: .ipinfoCore,
                enabled: true,
                requiresIPInfoToken: true
            ),
            PublicIPProvider(
                name: "IPinfo IPv4",
                url: "https://v4.api.ipinfo.io/lookup/me?token={ipinfoToken}",
                family: .ipv4,
                parser: .ipinfoCore,
                enabled: true,
                requiresIPInfoToken: true
            ),
            PublicIPProvider(
                name: "IPinfo IPv6",
                url: "https://v6.api.ipinfo.io/lookup/me?token={ipinfoToken}",
                family: .ipv6,
                parser: .ipinfoCore,
                enabled: true,
                requiresIPInfoToken: true
            ),
        ]

        let migrated = PublicIPProviderCatalog.normalized(providers)
        let auto = try XCTUnwrap(migrated.first { $0.name == "IPinfo Auto" })
        let ipv4 = try XCTUnwrap(migrated.first { $0.name == "IPinfo IPv4" })
        let ipv6 = try XCTUnwrap(migrated.first { $0.name == "IPinfo IPv6" })

        XCTAssertEqual(auto.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(ipv4.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(ipv6.url, "https://v6.ipinfo.io/json?token={ipinfoToken}")
        XCTAssertTrue(migrated.allSatisfy { $0.parser == .ipinfoLegacy })
    }

    func testMigratesCorrectedIPinfoURLsThatStillUseCoreParser() throws {
        let providers = [
            PublicIPProvider(
                name: "IPinfo Auto",
                url: "https://ipinfo.io/json?token={ipinfoToken}",
                family: .automatic,
                parser: .ipinfoCore,
                enabled: true,
                requiresIPInfoToken: true
            ),
            PublicIPProvider(
                name: "IPinfo IPv6",
                url: "https://v6.ipinfo.io/json?token={ipinfoToken}",
                family: .ipv6,
                parser: .ipinfoCore,
                enabled: true,
                requiresIPInfoToken: true
            ),
        ]

        let migrated = PublicIPProviderCatalog.normalized(providers)
        let auto = try XCTUnwrap(migrated.first { $0.name == "IPinfo Auto" })
        let ipv6 = try XCTUnwrap(migrated.first { $0.name == "IPinfo IPv6" })

        XCTAssertEqual(auto.parser, .ipinfoLegacy)
        XCTAssertEqual(ipv6.parser, .ipinfoLegacy)
    }

    func testDoesNotRewriteCustomCoreIPinfoProvider() {
        let provider = PublicIPProvider(
            name: "Paid IPinfo Core",
            url: "https://api.ipinfo.io/lookup/me?token={ipinfoToken}",
            family: .automatic,
            parser: .ipinfoCore,
            enabled: true,
            requiresIPInfoToken: true
        )

        let normalized = PublicIPProviderCatalog.normalized(provider)

        XCTAssertEqual(normalized.url, provider.url)
        XCTAssertEqual(normalized.parser, .ipinfoCore)
    }

    func testDefaultEgressTraceTargetsAreDestinationSpecific() throws {
        let targets = AppConfig.defaultEgressTraceTargets
        let first = try XCTUnwrap(targets.first)

        XCTAssertEqual(first.name, "ChatGPT")
        XCTAssertEqual(first.url, "https://chatgpt.com/cdn-cgi/trace")
        XCTAssertEqual(first.route, .system)
        XCTAssertEqual(first.parser, .cloudflareTrace)
        XCTAssertEqual(first.showInMenuBar, true)
        XCTAssertTrue(targets.contains { $0.route == .direct && $0.url == "https://chatgpt.com/cdn-cgi/trace" })
    }
}

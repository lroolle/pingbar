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

    func testDefaultIPinfoProvidersUseLegacyJSONEndpoints() {
        let providers = Dictionary(
            uniqueKeysWithValues: AppConfig.defaultPublicIPProviders
                .filter { $0.name.hasPrefix("IPinfo") }
                .map { ($0.name, $0) }
        )

        XCTAssertEqual(providers["IPinfo Auto"]?.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(providers["IPinfo IPv4"]?.url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(providers["IPinfo IPv6"]?.url, "https://v6.ipinfo.io/json?token={ipinfoToken}")
        XCTAssertTrue(providers.values.allSatisfy { $0.parser == .ipinfoLegacy })
        XCTAssertTrue(providers.values.allSatisfy(\.requiresIPInfoToken))
    }

    func testMigratesPersistedCoreIPinfoProvidersToLegacyJSONEndpoints() {
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

        XCTAssertEqual(migrated[0].url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(migrated[1].url, "https://ipinfo.io/json?token={ipinfoToken}")
        XCTAssertEqual(migrated[2].url, "https://v6.ipinfo.io/json?token={ipinfoToken}")
        XCTAssertTrue(migrated.allSatisfy { $0.parser == .ipinfoLegacy })
    }

    func testMigratesCorrectedIPinfoURLsThatStillUseCoreParser() {
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

        XCTAssertEqual(migrated[0].parser, .ipinfoLegacy)
        XCTAssertEqual(migrated[1].parser, .ipinfoLegacy)
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
}

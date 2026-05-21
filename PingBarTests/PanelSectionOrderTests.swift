import XCTest

final class PanelSectionOrderTests: XCTestCase {
    func testPingHostIDStaysStableWhenAddressChanges() {
        var host = PingHost(id: "stable-id", address: "1.1.1.1", label: "Cloudflare", enabled: true)

        host.address = "9.9.9.9"

        XCTAssertEqual(host.id, "stable-id")
    }

    func testDecodesOldPingHostWithoutStoredIDUsingAddressAsStableID() throws {
        let data = Data("""
        {
          "address": "1.1.1.1",
          "label": "Cloudflare",
          "enabled": true
        }
        """.utf8)

        let host = try JSONDecoder().decode(PingHost.self, from: data)

        XCTAssertEqual(host.id, "1.1.1.1")
        XCTAssertEqual(host.address, "1.1.1.1")
        XCTAssertEqual(host.label, "Cloudflare")
        XCTAssertTrue(host.enabled)
    }

    func testNormalizesPingHostsForEditableStableIDs() {
        let hosts = [
            PingHost(id: "same", address: " 1.1.1.1 ", label: " Cloudflare ", enabled: true),
            PingHost(id: "same", address: "8.8.8.8", label: "", enabled: true),
            PingHost(id: "empty", address: "  ", label: "Empty", enabled: true),
            PingHost(id: "duplicate-address", address: "1.1.1.1", label: "Duplicate", enabled: true),
        ]

        let normalized = AppConfig.normalizedPingHosts(hosts)

        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized[0].id, "same")
        XCTAssertEqual(normalized[0].address, "1.1.1.1")
        XCTAssertEqual(normalized[0].label, "Cloudflare")
        XCTAssertEqual(normalized[1].address, "8.8.8.8")
        XCTAssertEqual(normalized[1].label, "8.8.8.8")
        XCTAssertNotEqual(normalized[1].id, "same")
    }

    func testAppConfigPersistsNormalizedPingHosts() throws {
        let suiteName = "PingHostNormalization-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let config = AppConfig(defaults: defaults)

        config.pingHosts = [
            PingHost(id: "same", address: " 1.1.1.1 ", label: "", enabled: true),
            PingHost(id: "same", address: "8.8.8.8", label: "Google", enabled: true),
            PingHost(id: "duplicate", address: "1.1.1.1", label: "Duplicate", enabled: true),
        ]

        let stored = config.pingHosts
        let persisted = try XCTUnwrap(defaults.data(forKey: "pingHosts_v2"))
        let decoded = try JSONDecoder().decode([PingHost].self, from: persisted)

        XCTAssertEqual(stored.map(\.address), ["1.1.1.1", "8.8.8.8"])
        XCTAssertEqual(stored.map(\.label), ["1.1.1.1", "Google"])
        XCTAssertEqual(Set(stored.map(\.id)).count, stored.count)
        XCTAssertEqual(decoded, stored)
    }

    func testDefaultPanelOrderStartsWithHealthAndPerformanceEvidence() {
        XCTAssertEqual(Array(AppConfig.defaultPanelSectionOrder.prefix(3)), [
            .latency,
            .metricRollups,
            .throughput,
        ])
    }

    func testNormalizesPanelOrderByRemovingDuplicatesAndAddingMissingSectionsNearDefaultNeighbors() {
        let normalized = AppConfig.normalizedPanelSectionOrder([
            .wifi,
            .latency,
            .wifi,
        ])

        XCTAssertEqual(Array(normalized.prefix(4)), [.wifi, .latency, .metricRollups, .throughput])
        XCTAssertEqual(Set(normalized), Set(PanelSection.allCases))
        XCTAssertEqual(normalized.count, PanelSection.allCases.count)
    }

    func testMigratesOlderSavedPanelOrderByInsertingMetricRollupsAfterLatency() {
        let normalized = AppConfig.normalizedPanelSectionOrder([
            .latency,
            .throughput,
            .trafficUsage,
            .egress,
            .wifi,
            .processes,
            .speedTest,
            .speedHistory,
        ])

        XCTAssertEqual(Array(normalized.prefix(3)), [.latency, .metricRollups, .throughput])
    }
}

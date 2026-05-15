import XCTest

final class WarningEngineTests: XCTestCase {
    func testGatewayLatencyWarningBecomesCriticalAtThreshold() {
        var gateway = PingResult(id: "gateway", host: "192.168.1.1", label: "Gateway")
        gateway.record(latency: 80)

        let warnings = WarningEngine.evaluate(
            pingResults: ["192.168.1.1": gateway],
            wifiInfo: nil,
            proxyStatus: ProxyStatus(),
            gateway: "192.168.1.1"
        )

        XCTAssertEqual(warnings.first?.severity, .critical)
        XCTAssertEqual(warnings.first?.id, "gw-latency-critical")
    }

    func testWeakWiFiSignalProducesWarning() {
        let wifi = WiFiInfo(ssid: "Office", rssi: -75, noise: -92)

        let warnings = WarningEngine.evaluate(
            pingResults: [:],
            wifiInfo: wifi,
            proxyStatus: ProxyStatus(),
            gateway: nil
        )

        XCTAssertTrue(warnings.contains { $0.id == "rssi-caution" })
    }
}

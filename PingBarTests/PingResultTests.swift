import XCTest

final class PingResultTests: XCTestCase {
    func testRecordLatencyUpdatesReachabilityAndAverage() {
        var result = PingResult(id: "cloudflare", host: "1.1.1.1", label: "Cloudflare")

        result.record(latency: 10)
        result.record(latency: 20)

        XCTAssertTrue(result.isReachable)
        XCTAssertEqual(result.sent, 2)
        XCTAssertEqual(result.received, 2)
        XCTAssertEqual(result.latencyMs, 20)
        XCTAssertEqual(result.averageMs, 15)
        XCTAssertEqual(result.packetLoss, 0)
    }

    func testTimeoutContributesToRecentPacketLoss() {
        var result = PingResult(id: "gateway", host: "192.168.1.1", label: "Gateway")

        result.record(latency: 10)
        result.recordTimeout()

        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.sent, 2)
        XCTAssertEqual(result.received, 1)
        XCTAssertEqual(result.packetLoss, 0.5)
    }
}

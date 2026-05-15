import XCTest

final class FormatterTests: XCTestCase {
    func testBytesPerSecondUsesHumanUnits() {
        XCTAssertEqual(Fmt.bytesPerSec(0).value, "0")
        XCTAssertEqual(Fmt.bytesPerSec(0).unit, "B/s")
        XCTAssertEqual(Fmt.bytesPerSec(1_536).value, "1.5")
        XCTAssertEqual(Fmt.bytesPerSec(1_536).unit, "KB/s")
    }

    func testBitsPerSecondUsesNetworkUnits() {
        XCTAssertEqual(Fmt.bitsPerSec(950), "950 bps")
        XCTAssertEqual(Fmt.bitsPerSec(12_500_000), "12.5 Mbps")
    }

    func testLatencyAndPacketLossFormatting() {
        XCTAssertEqual(Fmt.latency(nil), "--")
        XCTAssertEqual(Fmt.latency(0.4), "< 1 ms")
        XCTAssertEqual(Fmt.packetLoss(0), "0%")
        XCTAssertEqual(Fmt.packetLoss(0.125), "12.5%")
    }
}

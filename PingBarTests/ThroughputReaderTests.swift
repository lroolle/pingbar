import XCTest

final class ThroughputReaderTests: XCTestCase {
    func testCounterDeltaReturnsDirectIncrease() {
        XCTAssertEqual(
            ThroughputReader.counterDelta(current: 2_500, previous: 1_000, elapsed: 1, linkSpeedMbps: 1_000),
            1_500
        )
    }

    func testCounterDeltaAcceptsPlausibleUInt32Wrap() {
        let previous = Int64(UInt32.max) - 128
        let current: Int64 = 256

        XCTAssertEqual(
            ThroughputReader.counterDelta(current: current, previous: previous, elapsed: 1, linkSpeedMbps: 1_000),
            385
        )
    }

    func testCounterDeltaRejectsCounterResetAsUsage() {
        XCTAssertNil(
            ThroughputReader.counterDelta(current: 100, previous: 2_000_000_000, elapsed: 1, linkSpeedMbps: 100)
        )
    }

    func testCounterDeltaRejectsImplausiblePositiveJump() {
        XCTAssertNil(
            ThroughputReader.counterDelta(
                current: 1_000_000_000,
                previous: 1_000,
                elapsed: 1,
                linkSpeedMbps: 10
            )
        )
    }

    func testCounterDeltaAcceptsPositiveDeltaWhenLinkSpeedIsUnknown() {
        XCTAssertEqual(
            ThroughputReader.counterDelta(current: 4_096, previous: 1_024, elapsed: 1, linkSpeedMbps: 0),
            3_072
        )
    }
}

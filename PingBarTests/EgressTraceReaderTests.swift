import Foundation
import XCTest

final class EgressTraceReaderTests: XCTestCase {
    func testParsesCloudflareTraceTarget() throws {
        let target = EgressTraceTarget(
            id: "chatgpt",
            name: "ChatGPT",
            url: "https://chatgpt.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: true,
            showInMenuBar: true
        )
        let data = Data("""
        ip=203.0.113.44
        colo=LAX
        loc=US
        warp=plus
        gateway=on
        http=http/3
        """.utf8)

        let endpoint = try XCTUnwrap(EgressTraceReader.parse(data, target: target))

        XCTAssertEqual(endpoint.ip, "203.0.113.44")
        XCTAssertEqual(endpoint.country, "US")
        XCTAssertEqual(endpoint.colo, "LAX")
        XCTAssertEqual(endpoint.warp, "plus")
        XCTAssertEqual(endpoint.gateway, "on")
        XCTAssertEqual(endpoint.httpProtocol, "http/3")
        XCTAssertEqual(endpoint.source, "ChatGPT")
    }

    func testParsesCRLFCloudflareTraceTargetWithoutCarriageReturns() throws {
        let target = EgressTraceTarget(
            id: "chatgpt",
            name: "ChatGPT",
            url: "https://chatgpt.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: true,
            showInMenuBar: true
        )
        let data = Data("ip=203.0.113.44\r\ncolo=LAX\r\nloc=US\r\nwarp=plus\r\nhttp=http/3\r\n".utf8)

        let endpoint = try XCTUnwrap(EgressTraceReader.parse(data, target: target))

        XCTAssertEqual(endpoint.ip, "203.0.113.44")
        XCTAssertEqual(endpoint.country, "US")
        XCTAssertEqual(endpoint.colo, "LAX")
        XCTAssertEqual(endpoint.warp, "plus")
        XCTAssertEqual(endpoint.httpProtocol, "http/3")
    }

    func testRejectsTraceWithoutIP() {
        let target = EgressTraceTarget(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("colo=SFO\nloc=US\n".utf8)

        XCTAssertNil(EgressTraceReader.parse(data, target: target))
    }

    func testRejectsTraceWithEmptyIP() {
        let target = EgressTraceTarget(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            route: .system,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("ip=\ncolo=SFO\nloc=US\n".utf8)

        XCTAssertNil(EgressTraceReader.parse(data, target: target))
    }
}

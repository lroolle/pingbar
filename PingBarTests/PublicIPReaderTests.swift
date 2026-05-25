import Foundation
import XCTest

final class PublicIPReaderTests: XCTestCase {
    func testParsesCloudflareTraceProviderResponse() throws {
        let provider = PublicIPProvider(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            family: .automatic,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("""
        ip=203.0.113.10
        colo=SFO
        loc=US
        warp=off
        gateway=off
        http=http/3
        """.utf8)

        let endpoint = try XCTUnwrap(PublicIPReader.parseProviderResponse(data, provider: provider))

        XCTAssertEqual(endpoint.ip, "203.0.113.10")
        XCTAssertEqual(endpoint.colo, "SFO")
        XCTAssertEqual(endpoint.country, "US")
        XCTAssertEqual(endpoint.warp, "off")
        XCTAssertEqual(endpoint.gateway, "off")
        XCTAssertEqual(endpoint.httpProtocol, "http/3")
        XCTAssertEqual(endpoint.source, "Trace")
    }

    func testParsesCRLFCloudflareTraceProviderResponseWithoutCarriageReturns() throws {
        let provider = PublicIPProvider(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            family: .automatic,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("ip=203.0.113.10\r\ncolo=SFO\r\nloc=US\r\nwarp=off\r\ngateway=off\r\nhttp=http/3\r\n".utf8)

        let endpoint = try XCTUnwrap(PublicIPReader.parseProviderResponse(data, provider: provider))

        XCTAssertEqual(endpoint.ip, "203.0.113.10")
        XCTAssertEqual(endpoint.colo, "SFO")
        XCTAssertEqual(endpoint.country, "US")
        XCTAssertEqual(endpoint.warp, "off")
        XCTAssertEqual(endpoint.gateway, "off")
        XCTAssertEqual(endpoint.httpProtocol, "http/3")
    }

    func testParsesIPinfoLegacyOrganization() throws {
        let provider = PublicIPProvider(
            id: "ipinfo",
            name: "IPinfo",
            url: "https://ipinfo.io/json",
            family: .automatic,
            parser: .ipinfoLegacy,
            enabled: true
        )
        let data = Data("""
        {
          "ip": "198.51.100.7",
          "city": "San Francisco",
          "region": "California",
          "country": "US",
          "org": "AS13335 Cloudflare, Inc."
        }
        """.utf8)

        let endpoint = try XCTUnwrap(PublicIPReader.parseProviderResponse(data, provider: provider))

        XCTAssertEqual(endpoint.ip, "198.51.100.7")
        XCTAssertEqual(endpoint.city, "San Francisco")
        XCTAssertEqual(endpoint.region, "California")
        XCTAssertEqual(endpoint.country, "US")
        XCTAssertEqual(endpoint.asn, 13_335)
        XCTAssertEqual(endpoint.organization, "Cloudflare, Inc.")
    }

    func testRejectsTraceWithoutIP() {
        let provider = PublicIPProvider(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            family: .automatic,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("colo=SFO\nloc=US\n".utf8)

        XCTAssertNil(PublicIPReader.parseProviderResponse(data, provider: provider))
    }

    func testRejectsTraceWithEmptyIP() {
        let provider = PublicIPProvider(
            id: "trace",
            name: "Trace",
            url: "https://example.com/cdn-cgi/trace",
            family: .automatic,
            parser: .cloudflareTrace,
            enabled: true
        )
        let data = Data("ip=\ncolo=SFO\nloc=US\n".utf8)

        XCTAssertNil(PublicIPReader.parseProviderResponse(data, provider: provider))
    }
}

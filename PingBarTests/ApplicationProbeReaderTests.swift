import Foundation
import XCTest

final class ApplicationProbeReaderTests: XCTestCase {
    override func tearDown() {
        MockApplicationProbeURLProtocol.storage.reset()
        super.tearDown()
    }

    func testHTTPHeadFailureFallsBackToRangeGET() async throws {
        MockApplicationProbeURLProtocol.storage.setResponses([
            MockApplicationProbeURLProtocol.Response(statusCode: 405, body: Data()),
            MockApplicationProbeURLProtocol.Response(statusCode: 206, body: Data("x".utf8)),
        ])
        let reader = ApplicationProbeReader { config in
            config.protocolClasses = [MockApplicationProbeURLProtocol.self]
        }
        let probe = ApplicationProbe(
            id: "app",
            name: "App",
            url: "https://example.com/health",
            route: .system,
            enabled: true
        )

        let results = await reader.read([probe])
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.statusCode, 206)
        XCTAssertEqual(result.error, "HEAD failed: HTTP 405")
        XCTAssertTrue(result.isHealthy)
        XCTAssertEqual(MockApplicationProbeURLProtocol.storage.requestMethods, ["HEAD", "GET"])
        let lastRangeHeader = try XCTUnwrap(MockApplicationProbeURLProtocol.storage.rangeHeaders.last)
        XCTAssertEqual(lastRangeHeader, "bytes=0-0")
    }
}

private final class MockApplicationProbeURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    static let storage = Storage()

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [Response] = []
        private var methods: [String] = []
        private var ranges: [String] = []

        var requestMethods: [String] {
            lock.lock()
            defer { lock.unlock() }
            return methods
        }

        var rangeHeaders: [String] {
            lock.lock()
            defer { lock.unlock() }
            return ranges
        }

        func setResponses(_ responses: [Response]) {
            lock.lock()
            self.responses = responses
            methods = []
            ranges = []
            lock.unlock()
        }

        func popResponse(for request: URLRequest) -> Response {
            lock.lock()
            defer { lock.unlock() }
            methods.append(request.httpMethod ?? "")
            if let range = request.value(forHTTPHeaderField: "Range") {
                ranges.append(range)
            }
            guard !responses.isEmpty else {
                return Response(statusCode: 500, body: Data())
            }
            return responses.removeFirst()
        }

        func reset() {
            lock.lock()
            responses = []
            methods = []
            ranges = []
            lock.unlock()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = Self.storage.popResponse(for: request)

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

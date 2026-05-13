import Foundation

final class PingReader {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func ping(host: String, timeout: Int = 5) -> Double? {
        let semaphore = DispatchSemaphore(value: 0)
        var latency: Double?

        let urlString: String
        if host.contains(".") && !host.contains("://") {
            urlString = "http://\(host)/"
        } else {
            urlString = host
        }

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = TimeInterval(timeout)

        let start = CFAbsoluteTimeGetCurrent()

        let task = session.dataTask(with: request) { _, response, error in
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            if let http = response as? HTTPURLResponse, (0...599).contains(http.statusCode) {
                latency = elapsed
            } else if error != nil {
                let connectTime = (CFAbsoluteTimeGetCurrent() - start) * 1000
                if connectTime < TimeInterval(timeout) * 1000 * 0.9 {
                    latency = connectTime
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return latency
    }
}

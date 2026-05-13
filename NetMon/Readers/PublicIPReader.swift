import Foundation

final class PublicIPReader {
    private struct IPResponse: Codable {
        let ip: String
    }

    private static let ipAPIs = [
        "https://api.ipify.org?format=json",
        "https://httpbin.org/ip",
        "https://ifconfig.me/ip",
    ]

    private let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private let proxySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func fetchDirectIP() async -> String? {
        await fetchIP(session: directSession)
    }

    func fetchProxyIP() async -> String? {
        await fetchIP(session: proxySession)
    }

    private func fetchIP(session: URLSession) async -> String? {
        for urlString in Self.ipAPIs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }

                if let resp = try? JSONDecoder().decode(IPResponse.self, from: data) {
                    return resp.ip
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let origin = json["origin"] as? String {
                    return origin.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
                }
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   text.count < 50, text.contains(".") || text.contains(":") {
                    return text
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

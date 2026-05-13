import Foundation

struct ProxyStatus {
    var isActive: Bool = false
    var httpProxy: String?
    var httpsProxy: String?
    var socksProxy: String?
    var proxyAppName: String?
    var proxyIP: String?
    var directIP: String?

    var summary: String {
        if !isActive { return "Direct" }
        if let app = proxyAppName { return app }
        if let hp = httpProxy { return hp }
        return "Proxy"
    }

    var ipsMatch: Bool {
        guard let p = proxyIP, let d = directIP, !p.isEmpty, !d.isEmpty else { return false }
        return p == d
    }
}

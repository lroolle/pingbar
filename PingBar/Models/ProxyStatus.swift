import Foundation

struct ProxyStatus {
    var isActive: Bool = false
    var httpProxy: String?
    var httpsProxy: String?
    var socksProxy: String?
    var proxyAppName: String?
    var proxyIP: String?
    var directIP: String?
    var httpProbeRoute: String?
    var httpsProbeRoute: String?

    var summary: String {
        guard hasConfiguredProxy else { return "Off" }
        if let app = proxyAppName { return app }
        if let hp = httpProxy { return "HTTP \(hp)" }
        if let hp = httpsProxy { return "HTTPS \(hp)" }
        if let sp = socksProxy { return "SOCKS \(sp)" }
        return "System Proxy"
    }

    var hasConfiguredProxy: Bool {
        httpProxy != nil || httpsProxy != nil || socksProxy != nil
    }

    var routeLabel: String {
        hasConfiguredProxy ? "System proxy" : "No system proxy"
    }

    var configuredProxySummary: String {
        let parts = [
            httpProxy.map { "HTTP \($0)" },
            httpsProxy.map { "HTTPS \($0)" },
            socksProxy.map { "SOCKS \($0)" },
        ].compactMap { $0 }

        guard !parts.isEmpty else { return summary }
        return parts.joined(separator: " · ")
    }

    var probeRouteSummary: String? {
        guard let httpsProbeRoute else { return nil }
        return "HTTPS \(httpsProbeRoute)"
    }

    var httpsProbeUsesDirect: Bool {
        httpsProbeRoute?.localizedCaseInsensitiveContains("DIRECT") == true
    }

    var ipsMatch: Bool {
        guard let p = proxyIP, let d = directIP, !p.isEmpty, !d.isEmpty else { return false }
        return p == d
    }
}

import Foundation
import AppKit
import SystemConfiguration

final class ProxyReader {
    private static let knownProxyApps = [
        "ClashX", "ClashX Pro", "clash", "Clash Verge",
        "Surge", "Surge Dashboard",
        "V2rayU", "V2RayXS", "Qv2ray",
        "Shadowrocket", "ShadowsocksX-NG",
        "Quantumult X",
        "Trojan-Qt5",
        "Proxifier",
    ]

    func read() -> ProxyStatus {
        var status = ProxyStatus()

        readEnvironment(&status)
        readSystemProxy(&status)
        detectProxyApp(&status)

        status.isActive = status.httpProxy != nil
                       || status.httpsProxy != nil
                       || status.socksProxy != nil

        return status
    }

    private func readEnvironment(_ status: inout ProxyStatus) {
        let env = ProcessInfo.processInfo.environment
        let httpKeys = ["HTTP_PROXY", "http_proxy"]
        let httpsKeys = ["HTTPS_PROXY", "https_proxy"]
        let socksKeys = ["ALL_PROXY", "all_proxy"]

        for k in httpKeys {
            if let v = env[k], !v.isEmpty { status.httpProxy = v; break }
        }
        for k in httpsKeys {
            if let v = env[k], !v.isEmpty { status.httpsProxy = v; break }
        }
        for k in socksKeys {
            if let v = env[k], !v.isEmpty { status.socksProxy = v; break }
        }
    }

    private func readSystemProxy(_ status: inout ProxyStatus) {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return }

        if let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int,
           let enabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int, enabled == 1 {
            status.httpProxy = status.httpProxy ?? "\(host):\(port)"
        }

        if let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int,
           let enabled = settings[kCFNetworkProxiesHTTPSEnable as String] as? Int, enabled == 1 {
            status.httpsProxy = status.httpsProxy ?? "\(host):\(port)"
        }

        if let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesSOCKSPort as String] as? Int,
           let enabled = settings[kCFNetworkProxiesSOCKSEnable as String] as? Int, enabled == 1 {
            status.socksProxy = status.socksProxy ?? "\(host):\(port)"
        }
    }

    private func detectProxyApp(_ status: inout ProxyStatus) {
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard let name = app.localizedName else { continue }
            if Self.knownProxyApps.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                status.proxyAppName = name
                return
            }
        }
    }
}

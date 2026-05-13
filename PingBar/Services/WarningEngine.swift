import Foundation

enum WarningEngine {
    struct Thresholds {
        var gatewayLatencyCaution: Double = 20
        var gatewayLatencyCritical: Double = 50
        var externalLatencyCaution: Double = 100
        var externalLatencyCritical: Double = 200
        var packetLossCaution: Double = 0.01
        var packetLossCritical: Double = 0.05
        var rssiCaution: Int = -70
        var rssiCritical: Int = -80
        var snrCaution: Int = 25
        var snrCritical: Int = 15
    }

    static let defaultThresholds = Thresholds()

    static func evaluate(
        pingResults: [String: PingResult],
        wifiInfo: WiFiInfo?,
        proxyStatus: ProxyStatus,
        gateway: String?,
        thresholds: Thresholds = defaultThresholds
    ) -> [Warning] {
        var warnings: [Warning] = []

        if let gw = gateway, let ping = pingResults[gw] {
            if let avg = ping.averageMs {
                if avg >= thresholds.gatewayLatencyCritical {
                    warnings.append(Warning(
                        id: "gw-latency-critical",
                        severity: .critical,
                        title: "Gateway latency \(Fmt.latency(avg))",
                        detail: "High latency to router may indicate local network congestion"
                    ))
                } else if avg >= thresholds.gatewayLatencyCaution {
                    warnings.append(Warning(
                        id: "gw-latency-caution",
                        severity: .caution,
                        title: "Gateway latency \(Fmt.latency(avg))",
                        detail: "Elevated latency to router"
                    ))
                }
            }
            if ping.packetLoss >= thresholds.packetLossCritical {
                warnings.append(Warning(
                    id: "gw-loss-critical",
                    severity: .critical,
                    title: "Gateway packet loss \(Fmt.packetLoss(ping.packetLoss))",
                    detail: "Significant packet loss indicates unstable connection"
                ))
            } else if ping.packetLoss >= thresholds.packetLossCaution {
                warnings.append(Warning(
                    id: "gw-loss-caution",
                    severity: .caution,
                    title: "Gateway packet loss \(Fmt.packetLoss(ping.packetLoss))"
                ))
            }
        }

        for (host, ping) in pingResults where host != gateway {
            if let avg = ping.averageMs {
                if avg >= thresholds.externalLatencyCritical {
                    warnings.append(Warning(
                        id: "ext-latency-\(host)-critical",
                        severity: .critical,
                        title: "\(ping.label) latency \(Fmt.latency(avg))"
                    ))
                } else if avg >= thresholds.externalLatencyCaution {
                    warnings.append(Warning(
                        id: "ext-latency-\(host)-caution",
                        severity: .caution,
                        title: "\(ping.label) latency \(Fmt.latency(avg))"
                    ))
                }
            }
            if ping.packetLoss >= thresholds.packetLossCritical {
                warnings.append(Warning(
                    id: "ext-loss-\(host)-critical",
                    severity: .critical,
                    title: "\(ping.label) packet loss \(Fmt.packetLoss(ping.packetLoss))"
                ))
            }
        }

        if let wifi = wifiInfo {
            if let rssi = wifi.rssi {
                if rssi <= thresholds.rssiCritical {
                    warnings.append(Warning(
                        id: "rssi-critical",
                        severity: .critical,
                        title: "Weak WiFi signal (\(rssi) dBm)",
                        detail: "Signal strength is very low, expect disconnections"
                    ))
                } else if rssi <= thresholds.rssiCaution {
                    warnings.append(Warning(
                        id: "rssi-caution",
                        severity: .caution,
                        title: "WiFi signal \(rssi) dBm",
                        detail: "Signal is below optimal range"
                    ))
                }
            }
            if let snr = wifi.snr {
                if snr <= thresholds.snrCritical {
                    warnings.append(Warning(
                        id: "snr-critical",
                        severity: .critical,
                        title: "Poor SNR (\(snr) dB)",
                        detail: "High noise floor relative to signal"
                    ))
                } else if snr <= thresholds.snrCaution {
                    warnings.append(Warning(
                        id: "snr-caution",
                        severity: .caution,
                        title: "Low SNR (\(snr) dB)"
                    ))
                }
            }
        }

        if proxyStatus.isActive && proxyStatus.ipsMatch {
            warnings.append(Warning(
                id: "proxy-ineffective",
                severity: .caution,
                title: "Proxy may not be routing traffic",
                detail: "Direct IP and proxy IP are the same"
            ))
        }

        warnings.sort { $0.severity > $1.severity }
        return warnings
    }
}

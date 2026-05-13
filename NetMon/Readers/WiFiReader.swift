import CoreWLAN
import CoreLocation

final class WiFiReader: NSObject, CLLocationManagerDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private var locationAuthorized = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorized = manager.authorizationStatus == .authorized
                          || manager.authorizationStatus == .authorizedAlways
    }

    func read(interface: String?) -> WiFiInfo? {
        let ifName = interface ?? "en0"
        guard let iface = wifiClient.interface(withName: ifName) else { return nil }

        var info = WiFiInfo()
        info.ssid = iface.ssid()
        info.bssid = iface.bssid()
        info.rssi = iface.rssiValue()
        info.noise = iface.noiseMeasurement()
        info.phyMode = phyModeString(iface.activePHYMode())
        info.security = securityString(iface.security())
        info.transmitRate = iface.transmitRate()

        if let ch = iface.wlanChannel() {
            info.channel = ch.channelNumber
            info.channelBand = bandString(ch.channelBand)
            info.channelWidth = widthString(ch.channelWidth)
        }

        if info.ssid == "<redacted>" {
            info.ssid = nil
        }

        return info
    }

    private func phyModeString(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a:  return "802.11a"
        case .mode11b:  return "802.11b"
        case .mode11g:  return "802.11g"
        case .mode11n:  return "802.11n"
        case .mode11ac: return "802.11ac"
        case .mode11ax: return "802.11ax"
        case .modeNone: return "none"
        @unknown default: return "unknown"
        }
    }

    private func bandString(_ band: CWChannelBand) -> String {
        switch band {
        case .band2GHz:    return "2.4 GHz"
        case .band5GHz:    return "5 GHz"
        case .band6GHz:    return "6 GHz"
        case .bandUnknown: return "unknown"
        @unknown default:  return "unknown"
        }
    }

    private func widthString(_ width: CWChannelWidth) -> String {
        switch width {
        case .width20MHz:  return "20 MHz"
        case .width40MHz:  return "40 MHz"
        case .width80MHz:  return "80 MHz"
        case .width160MHz: return "160 MHz"
        case .widthUnknown: return "unknown"
        @unknown default:   return "unknown"
        }
    }

    private func securityString(_ sec: CWSecurity) -> String {
        switch sec {
        case .none:               return "Open"
        case .WEP:                return "WEP"
        case .wpaPersonal:        return "WPA"
        case .wpaPersonalMixed:   return "WPA Mixed"
        case .wpa2Personal:       return "WPA2"
        case .personal:           return "WPA2/WPA3"
        case .wpa3Personal:       return "WPA3"
        case .wpa3Transition:     return "WPA3 Transition"
        case .wpaEnterprise:      return "WPA Enterprise"
        case .wpa2Enterprise:     return "WPA2 Enterprise"
        case .wpa3Enterprise:     return "WPA3 Enterprise"
        case .enterprise:         return "Enterprise"
        case .dynamicWEP:         return "Dynamic WEP"
        case .wpaEnterpriseMixed: return "WPA Enterprise Mixed"
        case .unknown:            return "unknown"
        @unknown default:         return "unknown (\(sec.rawValue))"
        }
    }
}

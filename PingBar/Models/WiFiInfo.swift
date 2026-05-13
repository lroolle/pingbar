import Foundation

struct WiFiInfo {
    var ssid: String?
    var bssid: String?
    var channel: Int?
    var channelBand: String?
    var channelWidth: String?
    var phyMode: String?
    var rssi: Int?
    var noise: Int?
    var security: String?
    var transmitRate: Double?

    var snr: Int? {
        guard let r = rssi, let n = noise else { return nil }
        return r - n
    }

    var signalQuality: SignalQuality {
        guard let r = rssi else { return .unknown }
        if r >= -50 { return .excellent }
        if r >= -60 { return .good }
        if r >= -70 { return .fair }
        if r >= -80 { return .weak }
        return .poor
    }

    enum SignalQuality: String {
        case excellent, good, fair, weak, poor, unknown
    }
}

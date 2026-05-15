import Foundation

struct SpeedTestHistoryEntry: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let preset: String
    let noProxy: Bool
    let server: String
    let location: String
    let wifiSSID: String?
    let wifiRSSI: Int?
    let wifiSNR: Int?
    let wifiChannel: Int?
    let wifiBand: String?
    let interface: String?
    let gateway: String?
    let directIP: String?
    let proxyIP: String?
    let directWarp: String?
    let proxyWarp: String?
    let directGateway: String?
    let proxyGateway: String?
    let latencyMs: Double
    let downloadBps: UInt64
    let uploadBps: UInt64

    init(
        date: Date,
        preset: String,
        noProxy: Bool,
        server: String,
        location: String,
        wifiSSID: String? = nil,
        wifiRSSI: Int? = nil,
        wifiSNR: Int? = nil,
        wifiChannel: Int? = nil,
        wifiBand: String? = nil,
        interface: String? = nil,
        gateway: String? = nil,
        directIP: String? = nil,
        proxyIP: String? = nil,
        directWarp: String? = nil,
        proxyWarp: String? = nil,
        directGateway: String? = nil,
        proxyGateway: String? = nil,
        latencyMs: Double,
        downloadBps: UInt64,
        uploadBps: UInt64
    ) {
        self.date = date
        self.preset = preset
        self.noProxy = noProxy
        self.server = server
        self.location = location
        self.wifiSSID = wifiSSID
        self.wifiRSSI = wifiRSSI
        self.wifiSNR = wifiSNR
        self.wifiChannel = wifiChannel
        self.wifiBand = wifiBand
        self.interface = interface
        self.gateway = gateway
        self.directIP = directIP
        self.proxyIP = proxyIP
        self.directWarp = directWarp
        self.proxyWarp = proxyWarp
        self.directGateway = directGateway
        self.proxyGateway = proxyGateway
        self.latencyMs = latencyMs
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        preset = try values.decode(String.self, forKey: .preset)
        noProxy = try values.decode(Bool.self, forKey: .noProxy)
        server = try values.decode(String.self, forKey: .server)
        location = try values.decode(String.self, forKey: .location)
        wifiSSID = try values.decodeIfPresent(String.self, forKey: .wifiSSID)
        wifiRSSI = try values.decodeIfPresent(Int.self, forKey: .wifiRSSI)
        wifiSNR = try values.decodeIfPresent(Int.self, forKey: .wifiSNR)
        wifiChannel = try values.decodeIfPresent(Int.self, forKey: .wifiChannel)
        wifiBand = try values.decodeIfPresent(String.self, forKey: .wifiBand)
        interface = try values.decodeIfPresent(String.self, forKey: .interface)
        gateway = try values.decodeIfPresent(String.self, forKey: .gateway)
        directIP = try values.decodeIfPresent(String.self, forKey: .directIP)
        proxyIP = try values.decodeIfPresent(String.self, forKey: .proxyIP)
        directWarp = try values.decodeIfPresent(String.self, forKey: .directWarp)
        proxyWarp = try values.decodeIfPresent(String.self, forKey: .proxyWarp)
        directGateway = try values.decodeIfPresent(String.self, forKey: .directGateway)
        proxyGateway = try values.decodeIfPresent(String.self, forKey: .proxyGateway)
        latencyMs = try values.decode(Double.self, forKey: .latencyMs)
        downloadBps = try values.decode(UInt64.self, forKey: .downloadBps)
        uploadBps = try values.decode(UInt64.self, forKey: .uploadBps)
    }
}

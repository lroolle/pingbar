import Foundation
import Combine

enum NetworkHealth: String {
    case good, degraded, poor, unknown

    var label: String {
        switch self {
        case .good:     return "Network OK"
        case .degraded: return "Degraded"
        case .poor:     return "Poor"
        case .unknown:  return "Checking..."
        }
    }
}

final class NetworkState: ObservableObject {
    @Published var uploadBytesPerSec: Int64 = 0
    @Published var downloadBytesPerSec: Int64 = 0
    @Published var linkSpeed: Double = 0

    @Published var pingResults: [String: PingResult] = [:]
    @Published var wifiInfo: WiFiInfo?
    @Published var proxyStatus = ProxyStatus()
    @Published var directIP: String?
    @Published var proxyIP: String?

    @Published var speedTestResult: NativeSpeedResult?
    @Published var isSpeedTestRunning = false
    @Published var speedTestError: String?

    @Published var activeWarnings: [Warning] = []

    let config = AppConfig.shared

    var health: NetworkHealth {
        let criticals = activeWarnings.filter { $0.severity == .critical }.count
        let cautions = activeWarnings.filter { $0.severity == .caution }.count
        if criticals > 0 { return .poor }
        if cautions > 0 { return .degraded }
        if pingResults.isEmpty { return .unknown }
        return .good
    }

    var allPingHostOrder: [String] {
        var hosts: [String] = []
        if let gw = cachedGateway { hosts.append(gw) }
        for h in config.pingHosts where h.enabled {
            hosts.append(h.address)
        }
        return hosts
    }

    private(set) var cachedInterface: String?
    private(set) var cachedGateway: String?

    private let throughputReader = ThroughputReader()
    private let pingReader = PingReader()
    private let wifiReader = WiFiReader()
    private let proxyReader = ProxyReader()
    private let publicIPReader = PublicIPReader()
    let speedTestRunner = SpeedTestRunner()

    private var throughputTimer: Timer?
    private var pingTimer: Timer?
    private var wifiTimer: Timer?
    private var proxyTimer: Timer?
    private var interfaceTimer: Timer?

    private let readerQueue = DispatchQueue(label: "pingbar.readers", qos: .utility)
    private var isPinging = false

    init() {
        refreshInterfaceInfo()
        wifiReader.requestLocationAccess()
        startReaders()
        refreshPublicIPs()
    }

    deinit {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer].forEach { $0?.invalidate() }
    }

    func restartReaders() {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer].forEach { $0?.invalidate() }
        startReaders()
    }

    private func refreshInterfaceInfo() {
        cachedInterface = PrimaryInterface.name()
        cachedGateway = PrimaryInterface.gatewayIP()
    }

    private func startReaders() {
        interfaceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshInterfaceInfo()
        }

        throughputTimer = Timer.scheduledTimer(withTimeInterval: config.throughputInterval, repeats: true) { [weak self] _ in
            self?.readThroughput()
        }

        pingTimer = Timer.scheduledTimer(withTimeInterval: config.pingInterval, repeats: true) { [weak self] _ in
            self?.readPing()
        }

        wifiTimer = Timer.scheduledTimer(withTimeInterval: config.wifiInterval, repeats: true) { [weak self] _ in
            self?.readWiFi()
        }

        proxyTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.readProxy()
        }

        readThroughput()
        readWiFi()
        readProxy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.readPing()
        }
    }

    private func readThroughput() {
        guard let iface = cachedInterface else { return }
        let reader = throughputReader
        readerQueue.async { [weak self] in
            let sample = reader.read(interface: iface)
            DispatchQueue.main.async {
                guard let self else { return }
                self.uploadBytesPerSec = sample.upload
                self.downloadBytesPerSec = sample.download
                if sample.linkSpeed > 0 { self.linkSpeed = sample.linkSpeed }
            }
        }
    }

    private func readPing() {
        guard !isPinging else { return }
        isPinging = true

        let hosts = allPingHosts()
        let reader = pingReader

        readerQueue.async { [weak self] in
            for (host, label) in hosts {
                let ms = reader.ping(host: host)
                DispatchQueue.main.async {
                    guard let self else { return }
                    var result = self.pingResults[host] ?? PingResult(id: host, host: host, label: label)
                    if let ms { result.record(latency: ms) }
                    else { result.recordTimeout() }
                    self.pingResults[host] = result
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.isPinging = false
                self?.evaluateWarnings()
            }
        }
    }

    private func readWiFi() {
        let iface = cachedInterface
        let reader = wifiReader
        readerQueue.async { [weak self] in
            let info = reader.read(interface: iface)
            DispatchQueue.main.async {
                guard let self else { return }
                self.wifiInfo = info
                self.evaluateWarnings()
            }
        }
    }

    private func readProxy() {
        let reader = proxyReader
        readerQueue.async { [weak self] in
            let status = reader.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.proxyStatus = status
                self.evaluateWarnings()
            }
        }
    }

    func refreshPublicIPs() {
        Task { [weak self] in
            guard let self else { return }
            async let direct = self.publicIPReader.fetchDirectIP()
            async let proxy = self.publicIPReader.fetchProxyIP()
            let (d, p) = await (direct, proxy)
            await MainActor.run {
                self.directIP = d
                self.proxyIP = p
            }
        }
    }

    func runSpeedTest(preset: SpeedTestPreset, noProxy: Bool) {
        guard !isSpeedTestRunning else { return }
        isSpeedTestRunning = true
        speedTestError = nil

        let runner = speedTestRunner
        Task {
            do {
                let result = try await runner.run(preset: preset, noProxy: noProxy)
                await MainActor.run { [weak self] in
                    self?.speedTestResult = result
                    self?.isSpeedTestRunning = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.speedTestError = error.localizedDescription
                    self?.isSpeedTestRunning = false
                }
            }
        }
    }

    func cancelSpeedTest() {
        speedTestRunner.cancel()
        isSpeedTestRunning = false
    }

    private func evaluateWarnings() {
        activeWarnings = WarningEngine.evaluate(
            pingResults: pingResults,
            wifiInfo: wifiInfo,
            proxyStatus: proxyStatus,
            gateway: cachedGateway
        )
    }

    private func allPingHosts() -> [(host: String, label: String)] {
        var hosts: [(String, String)] = []
        if let gw = cachedGateway {
            hosts.append((gw, "Gateway"))
        }
        for h in config.pingHosts where h.enabled {
            hosts.append((h.address, h.label))
        }
        return hosts
    }
}

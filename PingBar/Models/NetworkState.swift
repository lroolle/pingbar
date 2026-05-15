import Foundation
import Combine

enum NetworkHealth: String, Equatable {
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
    @Published var directEndpoint: PublicEndpointInfo?
    @Published var proxyEndpoint: PublicEndpointInfo?
    @Published var proxyProbeResults: [ProxyProbeResult] = []
    @Published var egressRoutes: [EgressRouteResult] = []
    @Published var isRefreshingPublicIPs = false

    @Published var speedTestResult: NativeSpeedResult?
    @Published var isSpeedTestRunning = false
    @Published var speedTestError: String?

    @Published var activeWarnings: [Warning] = []
    @Published var speedTestHistory: [SpeedTestHistoryEntry] = []
    @Published var topNetworkProcesses: [NetworkProcessSample] = []
    @Published var applicationProbeResults: [ApplicationProbeResult] = []
    private var dismissedWarningIDs = Set<String>()

    var downloadHistory = HistoryBuffer<Double>(capacity: 300)
    var uploadHistory = HistoryBuffer<Double>(capacity: 300)
    var latencyHistory: [String: HistoryBuffer<Double>] = [:]
    var latencySampleHistory: [String: HistoryBuffer<LatencySample>] = [:]

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

    @Published private(set) var cachedInterface: String?
    @Published private(set) var cachedInterfaceLabel: String?
    @Published private(set) var cachedGateway: String?

    private let throughputReader = ThroughputReader()
    private let pingReader = PingReader()
    private let wifiReader = WiFiReader()
    private let proxyReader = ProxyReader()
    private let publicIPReader = PublicIPReader()
    private let processNetworkReader = ProcessNetworkReader()
    private let applicationProbeReader = ApplicationProbeReader()
    let speedTestRunner = SpeedTestRunner()

    private var throughputTimer: Timer?
    private var pingTimer: Timer?
    private var wifiTimer: Timer?
    private var proxyTimer: Timer?
    private var interfaceTimer: Timer?
    private var processTimer: Timer?
    private var applicationProbeTimer: Timer?

    private let throughputQueue = DispatchQueue(label: "pingbar.readers.throughput", qos: .utility)
    private let pingQueue = DispatchQueue(label: "pingbar.readers.ping", qos: .utility)
    private let detailsQueue = DispatchQueue(label: "pingbar.readers.details", qos: .utility)
    private let processQueue = DispatchQueue(label: "pingbar.readers.processes", qos: .utility)
    private var isPinging = false
    private var isReadingApplicationProbes = false
    private var currentSpeedTestRunID: UUID?

    init() {
        loadSpeedTestHistory()
        refreshInterfaceInfo()
        wifiReader.requestLocationAccess()
        startReaders()
        refreshPublicIPs()
    }

    deinit {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer, processTimer, applicationProbeTimer].forEach { $0?.invalidate() }
    }

    func restartReaders() {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer, processTimer, applicationProbeTimer].forEach { $0?.invalidate() }
        startReaders()
    }

    func reloadPingHosts() {
        let activeHosts = Set(allPingHostOrder)
        pingResults = pingResults.filter { activeHosts.contains($0.key) }
        latencyHistory = latencyHistory.filter { activeHosts.contains($0.key) }
        latencySampleHistory = latencySampleHistory.filter { activeHosts.contains($0.key) }
        restartReaders()
    }

    private func refreshInterfaceInfo() {
        let previousInterface = cachedInterface
        let previousGateway = cachedGateway
        let interface = PrimaryInterface.name()
        cachedInterface = interface
        cachedInterfaceLabel = PrimaryInterface.displayLabel(for: interface)
        cachedGateway = PrimaryInterface.gatewayIP()

        if previousInterface != nil,
           previousInterface != interface || previousGateway != cachedGateway {
            pingResults.removeAll()
            latencyHistory.removeAll()
            latencySampleHistory.removeAll()
        }
    }

    private func startReaders() {
        interfaceTimer = Timer.scheduledTimer(withTimeInterval: config.networkDetailsInterval, repeats: true) { [weak self] _ in
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

        proxyTimer = Timer.scheduledTimer(withTimeInterval: config.networkDetailsInterval, repeats: true) { [weak self] _ in
            self?.readProxy()
        }

        processTimer = Timer.scheduledTimer(withTimeInterval: config.processStatsInterval, repeats: true) { [weak self] _ in
            self?.readNetworkProcesses()
        }

        applicationProbeTimer = Timer.scheduledTimer(withTimeInterval: config.networkDetailsInterval, repeats: true) { [weak self] _ in
            self?.readApplicationProbes()
        }

        readThroughput()
        readWiFi()
        readProxy()
        readNetworkProcesses()
        readApplicationProbes()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.readPing()
        }
    }

    private func readThroughput() {
        guard let iface = cachedInterface else { return }
        let reader = throughputReader
        throughputQueue.async { [weak self] in
            let sample = reader.read(interface: iface)
            DispatchQueue.main.async {
                guard let self else { return }
                self.uploadBytesPerSec = sample.upload
                self.downloadBytesPerSec = sample.download
                self.downloadHistory.append(Double(sample.download))
                self.uploadHistory.append(Double(sample.upload))
                if sample.linkSpeed > 0 { self.linkSpeed = sample.linkSpeed }
            }
        }
    }

    private func readPing() {
        guard !isPinging else { return }
        isPinging = true

        let hosts = allPingHosts()
        guard !hosts.isEmpty else {
            isPinging = false
            return
        }
        let reader = pingReader

        pingQueue.async { [weak self] in
            var measurements: [(index: Int, host: String, label: String, latency: Double?)] = []
            let lock = NSLock()

            DispatchQueue.concurrentPerform(iterations: hosts.count) { index in
                let (host, label) = hosts[index]
                let ms = reader.ping(host: host)
                lock.lock()
                measurements.append((index, host, label, ms))
                lock.unlock()
            }

            let ordered = measurements.sorted { $0.index < $1.index }

            DispatchQueue.main.async {
                guard let self else { return }
                for measurement in ordered {
                    let host = measurement.host
                    let label = measurement.label
                    let ms = measurement.latency
                    var result = self.pingResults[host] ?? PingResult(id: host, host: host, label: label)
                    if self.latencySampleHistory[host] == nil {
                        self.latencySampleHistory[host] = HistoryBuffer<LatencySample>(capacity: 240)
                    }
                    if let ms {
                        result.record(latency: ms)
                        if self.latencyHistory[host] == nil {
                            self.latencyHistory[host] = HistoryBuffer<Double>(capacity: 150)
                        }
                        self.latencyHistory[host]?.append(ms)
                        self.latencySampleHistory[host]?.append(LatencySample(date: Date(), latencyMs: ms))
                    } else {
                        result.recordTimeout()
                        self.latencySampleHistory[host]?.append(LatencySample(date: Date(), latencyMs: nil))
                    }
                    self.pingResults[host] = result
                }
                self.isPinging = false
                self.evaluateWarnings()
            }
        }
    }

    private func readWiFi() {
        let iface = cachedInterface
        let reader = wifiReader
        detailsQueue.async { [weak self] in
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
        detailsQueue.async { [weak self] in
            let status = reader.read()
            DispatchQueue.main.async {
                guard let self else { return }
                var merged = status
                merged.directIP = self.directIP
                merged.proxyIP = self.proxyIP
                self.proxyStatus = merged
                self.evaluateWarnings()
            }
        }
    }

    func readNetworkProcesses() {
        let reader = processNetworkReader
        let limit = config.topProcessCount
        processQueue.async { [weak self] in
            let processes = reader.read(limit: limit)
            DispatchQueue.main.async {
                self?.topNetworkProcesses = processes
            }
        }
    }

    func reloadApplicationProbes() {
        let activeIDs = Set(config.applicationProbes.filter(\.enabled).map(\.id))
        applicationProbeResults = applicationProbeResults.filter { activeIDs.contains($0.id) }
        readApplicationProbes()
    }

    private func readApplicationProbes() {
        guard !isReadingApplicationProbes else { return }
        let probes = config.applicationProbes.filter(\.enabled)
        guard !probes.isEmpty else {
            applicationProbeResults = []
            return
        }

        isReadingApplicationProbes = true
        let reader = applicationProbeReader
        Task { [weak self] in
            let results = await reader.read(probes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applicationProbeResults = results
                self.isReadingApplicationProbes = false
            }
        }
    }

    func refreshPublicIPs() {
        guard !isRefreshingPublicIPs else { return }
        isRefreshingPublicIPs = true
        Task { [weak self] in
            guard let self else { return }
            let status = self.proxyReader.read()
            let publicIPFamily = self.config.publicIPFamily
            let probes = self.config.proxyProbes.filter(\.enabled)
            let reader = self.publicIPReader
            async let direct = self.publicIPReader.fetchDirectEvidence(family: publicIPFamily)
            async let proxy = self.publicIPReader.fetchProxyEvidence(family: publicIPFamily)
            let (directEvidence, proxyEvidence) = await (direct, proxy)
            let configured = await self.fetchConfiguredProxyEndpoints(probes, reader: reader)
            let routes = self.makeEgressRoutes(
                directEvidence: directEvidence,
                proxyEvidence: proxyEvidence,
                configured: configured,
                status: status,
                publicIPFamily: publicIPFamily
            )
            await MainActor.run {
                self.directEndpoint = directEvidence.primaryEndpoint
                self.proxyEndpoint = proxyEvidence.primaryEndpoint
                self.proxyProbeResults = configured
                self.egressRoutes = routes
                self.directIP = directEvidence.primaryIP
                self.proxyIP = proxyEvidence.primaryIP
                var merged = status
                merged.directIP = directEvidence.primaryIP
                merged.proxyIP = proxyEvidence.primaryIP
                self.proxyStatus = merged
                self.isRefreshingPublicIPs = false
                self.evaluateWarnings()
            }
        }
    }

    private func fetchConfiguredProxyEndpoints(
        _ probes: [ProxyProbe],
        reader: PublicIPReader
    ) async -> [ProxyProbeResult] {
        var results: [ProxyProbeResult] = []
        for probe in probes {
            let evidence = await reader.fetchEvidence(via: probe)
            results.append(ProxyProbeResult(probe: probe, endpoint: evidence.primaryEndpoint, evidence: evidence))
        }
        return results
    }

    private func makeEgressRoutes(
        directEvidence: PublicIPEvidence,
        proxyEvidence: PublicIPEvidence,
        configured: [ProxyProbeResult],
        status: ProxyStatus,
        publicIPFamily: IPProbeFamily
    ) -> [EgressRouteResult] {
        var routes = [
            EgressRouteResult(
                id: "no-url-proxy",
                label: "Direct Probe",
                detail: "proxy disabled · \(publicIPFamily.label)",
                evidence: directEvidence
            ),
            EgressRouteResult(
                id: "system-settings",
                label: status.hasConfiguredProxy ? "System Proxy" : "System Route",
                detail: status.hasConfiguredProxy
                    ? "\(status.probeRouteSummary ?? status.configuredProxySummary) · \(publicIPFamily.label)"
                    : "macOS network settings · \(publicIPFamily.label)",
                evidence: proxyEvidence
            ),
        ]

        for result in configured {
            if let evidence = result.evidence {
                routes.append(EgressRouteResult(
                    id: result.probe.id,
                    label: result.probe.displayName,
                    detail: result.probe.routeDetail,
                    evidence: evidence
                ))
            }
        }

        return routes
    }

    func runSpeedTest(preset: SpeedTestPreset, noProxy: Bool) {
        guard !isSpeedTestRunning else { return }
        let runID = UUID()
        currentSpeedTestRunID = runID
        isSpeedTestRunning = true
        speedTestError = nil

        let runner = speedTestRunner
        Task {
            do {
                let result = try await runner.run(preset: preset, noProxy: noProxy)
                await MainActor.run { [weak self] in
                    guard let self, self.currentSpeedTestRunID == runID else { return }
                    self.speedTestResult = result
                    self.isSpeedTestRunning = false
                    self.currentSpeedTestRunID = nil
                    self.saveSpeedTestResult(result, preset: preset, noProxy: noProxy)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.currentSpeedTestRunID == runID else { return }
                    self.speedTestError = error.localizedDescription
                    self.isSpeedTestRunning = false
                    self.currentSpeedTestRunID = nil
                }
            }
        }
    }

    func cancelSpeedTest() {
        guard isSpeedTestRunning else { return }
        speedTestError = "Cancelling..."
        speedTestRunner.cancel()
    }

    private func evaluateWarnings() {
        let warnings = WarningEngine.evaluate(
            pingResults: pingResults,
            wifiInfo: wifiInfo,
            proxyStatus: proxyStatus,
            gateway: cachedGateway
        )
        activeWarnings = warnings.filter { !dismissedWarningIDs.contains($0.id) }
        let currentIDs = Set(warnings.map(\.id))
        dismissedWarningIDs = dismissedWarningIDs.intersection(currentIDs)
    }

    func clearWarnings() {
        dismissedWarningIDs.formUnion(activeWarnings.map(\.id))
        activeWarnings.removeAll()
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

    private func saveSpeedTestResult(_ result: NativeSpeedResult, preset: SpeedTestPreset, noProxy: Bool) {
        let entry = SpeedTestHistoryEntry(
            date: Date(),
            preset: preset.rawValue,
            noProxy: noProxy,
            server: result.server,
            location: result.location,
            wifiSSID: wifiInfo?.ssid,
            wifiRSSI: wifiInfo?.rssi,
            wifiSNR: wifiInfo?.snr,
            wifiChannel: wifiInfo?.channel,
            wifiBand: wifiInfo?.channelBand,
            interface: cachedInterfaceLabel ?? cachedInterface,
            gateway: cachedGateway,
            directIP: directIP,
            proxyIP: proxyIP,
            directWarp: directEndpoint?.warp,
            proxyWarp: proxyEndpoint?.warp,
            directGateway: directEndpoint?.gateway,
            proxyGateway: proxyEndpoint?.gateway,
            latencyMs: result.latencyMs,
            downloadBps: result.downloadBps,
            uploadBps: result.uploadBps
        )
        speedTestHistory.insert(entry, at: 0)
        if speedTestHistory.count > 20 { speedTestHistory = Array(speedTestHistory.prefix(20)) }

        if let data = try? JSONEncoder().encode(speedTestHistory) {
            UserDefaults.standard.set(data, forKey: "speedTestHistory")
        }
    }

    func loadSpeedTestHistory() {
        guard let data = UserDefaults.standard.data(forKey: "speedTestHistory"),
              let history = try? JSONDecoder().decode([SpeedTestHistoryEntry].self, from: data)
        else { return }
        speedTestHistory = history
    }

    func diagnosticReport() -> String {
        var lines: [String] = []
        func appendEndpoint(_ title: String, _ endpoint: PublicEndpointInfo?) {
            guard let endpoint else {
                lines.append("  \(title): --")
                return
            }

            lines.append("  \(title): \(endpoint.ip)")
            if let flag = endpoint.flagEmoji, let country = endpoint.countryCode {
                lines.append("    Country:  \(flag) \(country)")
            }
            if let location = endpoint.locationLabel {
                lines.append("    Location: \(location)")
            }
            if let network = endpoint.networkLabel {
                lines.append("    Network:  \(network)")
            }
            if let colo = endpoint.colo, !colo.isEmpty {
                lines.append("    CF Colo:  \(colo)")
            }
            if let warp = endpoint.warpLabel {
                lines.append("    WARP:     \(warp)")
            }
            if let gateway = endpoint.gatewayLabel {
                lines.append("    Gateway:  \(gateway)")
            }
            if let http = endpoint.httpProtocol, !http.isEmpty {
                lines.append("    HTTP:     \(http)")
            }
            if let source = endpoint.source {
                lines.append("    Source:   \(source)")
            }
        }

        func appendRouteEvidence(_ route: EgressRouteResult) {
            let title = route.detail.map { "\(route.label) [\($0)]" } ?? route.label
            appendEndpoint(title, route.endpoint)
            lines.append("    Confidence: \(route.evidence.confidence.label)")

            let sources = route.evidence.probes.map { probe -> String in
                let suffix = probe.diagnostic ? "*" : ""
                return "\(probe.source)\(suffix)=\(probe.ip ?? "no-ip")"
            }
            if !sources.isEmpty {
                lines.append("    Evidence:   \(sources.joined(separator: ", "))")
            }
            if route.evidence.observedIPs.count > 1 {
                lines.append("    Observed:   \(route.evidence.observedIPs.joined(separator: ", "))")
            }
        }

        func recentLosses(for host: String) -> Int {
            latencySampleHistory[host]?.values.filter { $0.isLoss }.count ?? 0
        }

        lines.append("PingBar Network Evidence Report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        lines.append("== Summary ==")
        lines.append("  Health: \(health.label)")
        lines.append("  Warnings: \(activeWarnings.count)")
        if let wifi = wifiInfo, let ssid = wifi.ssid {
            lines.append("  Wi-Fi: \(ssid)")
        }
        if let iface = cachedInterfaceLabel ?? cachedInterface {
            lines.append("  Interface: \(iface)")
        }
        if let directIP {
            if let proxyIP, proxyIP != directIP {
                let pathLabel = proxyStatus.hasConfiguredProxy ? "system proxy" : "system egress"
                lines.append("  Public IP: \(pathLabel) differs (\(directIP) -> \(proxyIP))")
            } else {
                lines.append("  Public IP: \(directIP)")
            }
        }
        lines.append("")

        if !activeWarnings.isEmpty {
            lines.append("== Warnings ==")
            for w in activeWarnings {
                lines.append("  [\(String(describing: w.severity))] \(w.title)")
                if let detail = w.detail {
                    lines.append("    \(detail)")
                }
            }
            lines.append("")
        }

        lines.append("== Interface ==")
        if let ssid = wifiInfo?.ssid { lines.append("  Wi-Fi:     \(ssid)") }
        if let iface = cachedInterfaceLabel ?? cachedInterface { lines.append("  Interface: \(iface)") }
        if let gateway = cachedGateway { lines.append("  Gateway:   \(gateway)") }
        lines.append("")

        lines.append("== Public Egress ==")
        lines.append("  System Proxy: \(proxyStatus.hasConfiguredProxy ? proxyStatus.configuredProxySummary : "Off")")
        if let route = proxyStatus.httpProbeRoute {
            lines.append("  CFNetwork HTTP probe route: \(route)")
        }
        if let route = proxyStatus.httpsProbeRoute {
            lines.append("  CFNetwork HTTPS probe route: \(route)")
        }
        lines.append("  No Proxy probe: URLSession with HTTP/HTTPS/SOCKS/PAC proxy settings disabled")
        lines.append("  System Egress probe: URLSession with macOS network settings")
        lines.append("  Note: VPN/WARP/TUN routes are below URLSession proxy settings; no-proxy mode does not bypass them.")

        if !egressRoutes.isEmpty {
            lines.append("")
            lines.append("  Probes:")
            for route in egressRoutes {
                appendRouteEvidence(route)
            }
        } else {
            appendEndpoint("No Proxy IP", directEndpoint)
            if proxyStatus.hasConfiguredProxy || proxyEndpoint != directEndpoint {
                appendEndpoint(proxyStatus.hasConfiguredProxy ? "System Proxy IP" : "System Egress IP", proxyEndpoint)
            }
        }
        lines.append("")

        lines.append("== Throughput ==")
        lines.append("  Download: \(Fmt.throughputCompact(downloadBytesPerSec))")
        lines.append("  Upload:   \(Fmt.throughputCompact(uploadBytesPerSec))")
        if linkSpeed > 0 { lines.append("  Link:     \(Int(linkSpeed)) Mbps") }
        lines.append("")

        lines.append("== Latency Evidence ==")
        for host in allPingHostOrder {
            if let ping = pingResults[host] {
                let lat = Fmt.latency(ping.latencyMs)
                let avg = Fmt.latency(ping.averageMs)
                let loss = Fmt.packetLoss(ping.packetLoss)
                let jit = ping.jitterMs.map { String(format: "%.1fms", $0) } ?? "--"
                lines.append("  \(ping.label) (\(host))")
                lines.append("    Last: \(lat)  Avg: \(avg)  Jitter: \(jit)  Loss: \(loss)")
                lines.append("    Samples: sent=\(ping.sent) received=\(ping.received) recent_losses=\(recentLosses(for: host))")
            }
        }
        lines.append("")

        if let wifi = wifiInfo {
            lines.append("== Wi-Fi Radio ==")
            if let ssid = wifi.ssid { lines.append("  SSID:     \(ssid)") }
            if let bssid = wifi.bssid { lines.append("  BSSID:    \(bssid)") }
            if let ch = wifi.channel, let band = wifi.channelBand, let width = wifi.channelWidth {
                lines.append("  Channel:  \(ch) (\(band), \(width))")
            }
            if let phy = wifi.phyMode { lines.append("  Standard: \(phy)") }
            if let rssi = wifi.rssi { lines.append("  Signal:   \(rssi) dBm") }
            if let noise = wifi.noise { lines.append("  Noise:    \(noise) dBm") }
            if let snr = wifi.snr { lines.append("  SNR:      \(snr) dB") }
            if let rate = wifi.transmitRate { lines.append("  Tx Rate:  \(Int(rate)) Mbps") }
            lines.append("  Quality:  \(wifi.signalQuality.rawValue)")
            lines.append("")
        }

        if let result = speedTestResult {
            lines.append("== Last Speed Test ==")
            lines.append("  Status:   \(result.status)")
            lines.append("  Server:   \(result.server) (\(result.location))")
            lines.append("  Latency:  \(Fmt.latency(result.latencyMs))")
            if result.downloadBps > 0 { lines.append("  Download: \(Fmt.bitsPerSec(result.downloadBps))") }
            if result.uploadBps > 0 { lines.append("  Upload:   \(Fmt.bitsPerSec(result.uploadBps))") }
            if let error = result.error { lines.append("  Partial:  \(error)") }
            lines.append("")
        }

        if !speedTestHistory.isEmpty {
            lines.append("== Recent Speed Test Log ==")
            for entry in speedTestHistory.prefix(8) {
                lines.append("  \(ISO8601DateFormatter().string(from: entry.date))")
                lines.append("    Preset: \(entry.preset)  Mode: \(entry.noProxy ? "No Proxy" : "System Egress")")
                if let ssid = entry.wifiSSID { lines.append("    Wi-Fi: \(ssid)") }
                if let rssi = entry.wifiRSSI { lines.append("    RSSI:   \(rssi) dBm") }
                if let snr = entry.wifiSNR { lines.append("    SNR:    \(snr) dB") }
                if let channel = entry.wifiChannel {
                    let band = entry.wifiBand.map { " \($0)" } ?? ""
                    lines.append("    Radio:  channel \(channel)\(band)")
                }
                if let iface = entry.interface { lines.append("    Iface:  \(iface)") }
                if let gateway = entry.gateway { lines.append("    GW:     \(gateway)") }
                if let directIP = entry.directIP { lines.append("    No Proxy: \(directIP)") }
                if let proxyIP = entry.proxyIP, proxyIP != entry.directIP { lines.append("    System Egress: \(proxyIP)") }
                if let directWarp = entry.directWarp { lines.append("    No Proxy WARP: \(directWarp)") }
                if let proxyWarp = entry.proxyWarp, proxyWarp != entry.directWarp { lines.append("    System Egress WARP: \(proxyWarp)") }
                if let directGateway = entry.directGateway, directGateway != "off" { lines.append("    No Proxy Gateway: \(directGateway)") }
                if let proxyGateway = entry.proxyGateway, proxyGateway != "off", proxyGateway != entry.directGateway { lines.append("    System Egress Gateway: \(proxyGateway)") }
                lines.append("    Server: \(entry.server) \(entry.location)")
                lines.append("    Result: \(Fmt.latency(entry.latencyMs))  ↓\(Fmt.bitsPerSec(entry.downloadBps))  ↑\(Fmt.bitsPerSec(entry.uploadBps))")
            }
        }

        return lines.joined(separator: "\n")
    }
}

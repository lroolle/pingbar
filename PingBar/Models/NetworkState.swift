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
    @Published var egressTraceResults: [EgressTraceResult] = []
    @Published var isRefreshingPublicIPs = false

    @Published var speedTestResult: NativeSpeedResult?
    @Published var isSpeedTestRunning = false
    @Published var speedTestError: String?

    @Published var activeWarnings: [Warning] = []
    @Published var speedTestHistory: [SpeedTestHistoryEntry] = []
    @Published var topNetworkProcesses: [NetworkProcessSample] = []
    @Published var applicationProbeResults: [ApplicationProbeResult] = []
    @Published var trafficUsageRecords: [NetworkTrafficUsage] = []
    @Published var trafficUsageBuckets: [NetworkTrafficUsageBucket] = []
    @Published var currentTrafficIdentity: NetworkTrafficIdentity?
    @Published var networkMetricSummaries: [NetworkMetricSummary] = []
    @Published var recentNetworkMetricSamples: [NetworkMetricSample] = []
    private var dismissedWarningIDs = Set<String>()

    var downloadHistory = HistoryBuffer<Double>(capacity: 300)
    var uploadHistory = HistoryBuffer<Double>(capacity: 300)
    var latencyHistory: [String: HistoryBuffer<Double>] = [:]
    var latencySampleHistory: [String: HistoryBuffer<LatencySample>] = [:]

    let config = AppConfig.shared

    var recentThroughputAggregate: ThroughputAggregate? {
        let sampleCount = max(2, min(120, Int(60 / max(config.throughputInterval, 0.5))))
        let uploads = Array(uploadHistory.values.suffix(sampleCount))
        let downloads = Array(downloadHistory.values.suffix(sampleCount))
        guard !uploads.isEmpty, !downloads.isEmpty else { return nil }

        let avgUpload = uploads.reduce(0, +) / Double(uploads.count)
        let avgDownload = downloads.reduce(0, +) / Double(downloads.count)
        let observedWindow = Int(round(Double(min(uploads.count, downloads.count)) * config.throughputInterval))

        return ThroughputAggregate(
            sampleCount: min(uploads.count, downloads.count),
            windowSeconds: min(60, max(1, observedWindow)),
            averageUpload: Int64(avgUpload),
            averageDownload: Int64(avgDownload),
            peakUpload: Int64(uploads.max() ?? 0),
            peakDownload: Int64(downloads.max() ?? 0)
        )
    }

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
    private let egressTraceReader = EgressTraceReader()
    private let trafficUsageStore = TrafficUsageStore()
    private let networkMetricStore = NetworkMetricStore()
    let speedTestRunner = SpeedTestRunner()

    private var throughputTimer: Timer?
    private var pingTimer: Timer?
    private var wifiTimer: Timer?
    private var proxyTimer: Timer?
    private var interfaceTimer: Timer?
    private var processTimer: Timer?
    private var applicationProbeTimer: Timer?
    private var egressTraceTimer: Timer?

    private let throughputQueue = DispatchQueue(label: "pingbar.readers.throughput", qos: .utility)
    private let pingQueue = DispatchQueue(label: "pingbar.readers.ping", qos: .utility)
    private let detailsQueue = DispatchQueue(label: "pingbar.readers.details", qos: .utility)
    private let processQueue = DispatchQueue(label: "pingbar.readers.processes", qos: .utility)
    private var isPinging = false
    private var isReadingApplicationProbes = false
    private var isReadingEgressTraces = false
    private var publicIPRefreshGeneration: UInt64 = 0
    private var pendingPublicIPRefresh = false
    private var currentSpeedTestRunID: UUID?
    private let warningMetricWindow: TimeInterval = 5 * 60

    init() {
        loadSpeedTestHistory()
        let trafficSnapshot = trafficUsageStore.currentSnapshot
        trafficUsageRecords = trafficSnapshot.records
        trafficUsageBuckets = trafficSnapshot.buckets
        let metricSnapshot = networkMetricStore.currentSnapshot
        recentNetworkMetricSamples = metricSnapshot.samples
        networkMetricSummaries = metricSnapshot.summaries
        refreshInterfaceInfo()
        wifiReader.requestLocationAccess()
        startReaders()
        refreshPublicIPs()
    }

    deinit {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer, processTimer, applicationProbeTimer, egressTraceTimer].forEach { $0?.invalidate() }
    }

    func restartReaders() {
        [throughputTimer, pingTimer, wifiTimer, proxyTimer, interfaceTimer, processTimer, applicationProbeTimer, egressTraceTimer].forEach { $0?.invalidate() }
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

        if previousInterface != nil, previousInterface != interface {
            wifiInfo = nil
        }
        currentTrafficIdentity = trafficIdentity(interface: interface)
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

        egressTraceTimer = Timer.scheduledTimer(withTimeInterval: config.networkDetailsInterval, repeats: true) { [weak self] _ in
            self?.readEgressTraces()
        }

        readThroughput()
        readWiFi()
        readProxy()
        readNetworkProcesses()
        readApplicationProbes()
        readEgressTraces()
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
                guard self.cachedInterface == iface else { return }
                let identity = self.trafficIdentity(interface: iface)
                self.uploadBytesPerSec = sample.upload
                self.downloadBytesPerSec = sample.download
                self.downloadHistory.append(Double(sample.download))
                self.uploadHistory.append(Double(sample.upload))
                if sample.linkSpeed > 0 { self.linkSpeed = sample.linkSpeed }
                if let identity {
                    self.currentTrafficIdentity = identity
                    let snapshot = self.trafficUsageStore.record(sample: sample, identity: identity)
                    self.trafficUsageRecords = snapshot.records
                    self.trafficUsageBuckets = snapshot.buckets
                    if let metric = NetworkMetricSample.throughput(date: Date(), sample: sample, identity: identity) {
                        self.recordNetworkMetrics([metric])
                    }
                }
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
                let sampleDate = Date()
                let identity = self.currentTrafficIdentity
                var metricSamples: [NetworkMetricSample] = []
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
                    metricSamples.append(NetworkMetricSample.latency(
                        date: sampleDate,
                        host: host,
                        label: label,
                        latencyMs: ms,
                        isGateway: host == self.cachedGateway,
                        identity: identity
                    ))
                }
                self.recordNetworkMetrics(metricSamples)
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
                guard self.cachedInterface == iface else { return }
                let previousID = self.currentTrafficIdentity?.id
                self.wifiInfo = info
                let nextIdentity = self.trafficIdentity(interface: iface)
                self.currentTrafficIdentity = nextIdentity
                if let previousID,
                   let nextID = nextIdentity?.id,
                   previousID != nextID {
                    self.resetThroughputBaseline()
                }
                if let info,
                   let metric = NetworkMetricSample.wifiSignal(date: Date(), info: info, identity: nextIdentity) {
                    self.recordNetworkMetrics([metric])
                }
                self.evaluateWarnings()
            }
        }
    }

    private func trafficIdentity(interface: String?) -> NetworkTrafficIdentity? {
        guard let interface else { return nil }
        return NetworkTrafficIdentity(
            interfaceName: interface,
            interfaceLabel: cachedInterfaceLabel,
            wifiInfo: wifiInfo
        )
    }

    private func resetThroughputBaseline() {
        let reader = throughputReader
        throughputQueue.async {
            reader.reset()
        }
    }

    func clearTrafficUsage() {
        let snapshot = trafficUsageStore.reset()
        trafficUsageRecords = snapshot.records
        trafficUsageBuckets = snapshot.buckets
    }

    func flushTrafficUsage() {
        trafficUsageStore.flush()
    }

    func flushNetworkMetrics() {
        networkMetricStore.flush()
    }

    func trafficUsageAggregates(groupedBy aggregation: NetworkTrafficAggregation) -> [NetworkTrafficAggregate] {
        NetworkTrafficAggregate.make(
            records: trafficUsageRecords,
            buckets: trafficUsageBuckets,
            groupedBy: aggregation,
            currentIdentity: currentTrafficIdentity
        )
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

    func reloadEgressTraceTargets() {
        let activeIDs = Set(config.egressTraceTargets.filter(\.enabled).map(\.id))
        egressTraceResults = egressTraceResults.filter { activeIDs.contains($0.id) }
        readEgressTraces()
    }

    func refreshEgressTraces() {
        readEgressTraces()
    }

    private func readApplicationProbes() {
        guard !isReadingApplicationProbes else { return }
        let probes = config.applicationProbes.filter(\.enabled)
        guard !probes.isEmpty else {
            applicationProbeResults = []
            isReadingApplicationProbes = false
            evaluateWarnings()
            return
        }

        isReadingApplicationProbes = true
        let reader = applicationProbeReader
        Task { [weak self] in
            let results = await reader.read(probes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let activeProbes = self.config.applicationProbes.filter(\.enabled)
                guard activeProbes == probes else {
                    self.isReadingApplicationProbes = false
                    self.readApplicationProbes()
                    return
                }
                let activeIDs = Set(activeProbes.map(\.id))
                let filteredResults = results.filter { activeIDs.contains($0.id) }
                self.applicationProbeResults = filteredResults
                let identity = self.currentTrafficIdentity
                let metricSamples = filteredResults.flatMap { result in
                    [NetworkMetricSample.applicationProbe(result, identity: identity)]
                        + NetworkMetricSample.applicationProbePhaseSamples(result, identity: identity)
                }
                self.recordNetworkMetrics(metricSamples)
                self.isReadingApplicationProbes = false
                self.evaluateWarnings()
            }
        }
    }

    private func readEgressTraces() {
        guard !isReadingEgressTraces else { return }
        let targets = config.egressTraceTargets.filter(\.enabled)
        guard !targets.isEmpty else {
            egressTraceResults = []
            isReadingEgressTraces = false
            return
        }

        isReadingEgressTraces = true
        let reader = egressTraceReader
        Task { [weak self] in
            let results = await reader.read(targets)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let activeTargets = self.config.egressTraceTargets.filter(\.enabled)
                guard activeTargets == targets else {
                    self.isReadingEgressTraces = false
                    self.readEgressTraces()
                    return
                }
                let activeIDs = Set(activeTargets.map(\.id))
                self.egressTraceResults = results.filter { activeIDs.contains($0.id) }
                self.isReadingEgressTraces = false
            }
        }
    }

    func refreshPublicIPs() {
        publicIPRefreshGeneration &+= 1
        let generation = publicIPRefreshGeneration
        guard !isRefreshingPublicIPs else {
            pendingPublicIPRefresh = true
            return
        }
        isRefreshingPublicIPs = true
        pendingPublicIPRefresh = false
        let proxyReader = proxyReader
        let publicIPReader = publicIPReader
        let publicIPFamily = config.publicIPFamily
        let publicIPContext = PublicIPProbeContext(
            providers: config.publicIPProviders,
            ipInfoToken: config.ipInfoToken
        )
        let probes = config.proxyProbes.filter(\.enabled)
        Task { [weak self] in
            let status = proxyReader.read()
            async let direct = publicIPReader.fetchDirectEvidence(
                family: publicIPFamily,
                context: publicIPContext
            )
            async let proxy = publicIPReader.fetchProxyEvidence(
                family: publicIPFamily,
                context: publicIPContext
            )
            let (directEvidence, proxyEvidence) = await (direct, proxy)
            let configured = await Self.fetchConfiguredProxyEndpoints(
                probes,
                reader: publicIPReader,
                context: publicIPContext
            )
            let routes = Self.makeEgressRoutes(
                directEvidence: directEvidence,
                proxyEvidence: proxyEvidence,
                configured: configured,
                status: status,
                publicIPFamily: publicIPFamily
            )
            await MainActor.run {
                guard let self else { return }
                guard generation == self.publicIPRefreshGeneration else {
                    self.isRefreshingPublicIPs = false
                    if self.pendingPublicIPRefresh {
                        self.pendingPublicIPRefresh = false
                        self.refreshPublicIPs()
                    }
                    return
                }
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
                if self.pendingPublicIPRefresh {
                    self.pendingPublicIPRefresh = false
                    self.refreshPublicIPs()
                }
            }
        }
    }

    private static func fetchConfiguredProxyEndpoints(
        _ probes: [ProxyProbe],
        reader: PublicIPReader,
        context: PublicIPProbeContext
    ) async -> [ProxyProbeResult] {
        var results: [ProxyProbeResult] = []
        for probe in probes {
            let evidence = await reader.fetchEvidence(via: probe, context: context)
            results.append(ProxyProbeResult(probe: probe, endpoint: evidence.primaryEndpoint, evidence: evidence))
        }
        return results
    }

    private static func makeEgressRoutes(
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
                    self.recordSpeedTestMetrics(result, noProxy: noProxy)
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
            gateway: cachedGateway,
            applicationProbeResults: applicationProbeResults,
            metricSummaries: warningMetricSummaries,
            thresholds: warningThresholds
        )
        activeWarnings = warnings.filter { !dismissedWarningIDs.contains($0.id) }
        let currentIDs = Set(warnings.map(\.id))
        dismissedWarningIDs = dismissedWarningIDs.intersection(currentIDs)
    }

    private var warningThresholds: WarningEngine.Thresholds {
        var thresholds = WarningEngine.defaultThresholds
        thresholds.gatewayLatencyCaution = config.gatewayLatencyCaution
        thresholds.gatewayLatencyCritical = config.gatewayLatencyCritical
        thresholds.externalLatencyCaution = config.externalLatencyCaution
        thresholds.externalLatencyCritical = config.externalLatencyCritical
        thresholds.packetLossCaution = config.packetLossCaution
        thresholds.packetLossCritical = config.packetLossCritical
        thresholds.appDirectLatencyCaution = config.appDirectLatencyCaution
        thresholds.appDirectLatencyCritical = config.appDirectLatencyCritical
        thresholds.appSystemLatencyCaution = config.appSystemLatencyCaution
        thresholds.appSystemLatencyCritical = config.appSystemLatencyCritical
        return thresholds
    }

    private var warningMetricSummaries: [NetworkMetricSummary] {
        currentNetworkMetricSummaries(from: networkMetricStore.summaries(window: warningMetricWindow))
    }

    private func metricSummaries(window: TimeInterval) -> [NetworkMetricSummary] {
        currentNetworkMetricSummaries(from: networkMetricStore.summaries(window: window))
    }

    var currentNetworkMetricSummaries: [NetworkMetricSummary] {
        currentNetworkMetricSummaries(from: networkMetricSummaries)
    }

    private func currentNetworkMetricSummaries(from summaries: [NetworkMetricSummary]) -> [NetworkMetricSummary] {
        NetworkMetricFilters.currentNetworkSummaries(
            summaries,
            currentNetworkID: currentTrafficIdentity?.id
        )
    }

    private func recordNetworkMetrics(_ samples: [NetworkMetricSample]) {
        guard !samples.isEmpty else { return }
        let snapshot = networkMetricStore.record(samples)
        recentNetworkMetricSamples = snapshot.samples
        networkMetricSummaries = snapshot.summaries
    }

    private func recordSpeedTestMetrics(_ result: NativeSpeedResult, noProxy: Bool) {
        let date = Date()
        let identity = currentTrafficIdentity
        var samples = [
            NetworkMetricSample.speedTest(
                date: date,
                kind: .speedTestLatency,
                value: result.latencyMs,
                server: result.server,
                location: result.location,
                status: result.status,
                identity: identity,
                noProxy: noProxy
            ),
        ]
        if result.downloadBps > 0 {
            samples.append(NetworkMetricSample.speedTest(
                date: date,
                kind: .speedTestDownload,
                value: Double(result.downloadBps),
                server: result.server,
                location: result.location,
                status: result.status,
                identity: identity,
                noProxy: noProxy
            ))
        }
        if result.uploadBps > 0 {
            samples.append(NetworkMetricSample.speedTest(
                date: date,
                kind: .speedTestUpload,
                value: Double(result.uploadBps),
                server: result.server,
                location: result.location,
                status: result.status,
                identity: identity,
                noProxy: noProxy
            ))
        }
        recordNetworkMetrics(samples)
    }

    func refreshWarnings() {
        evaluateWarnings()
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

        func appendMetricSummary(_ summary: NetworkMetricSummary, indent: String = "  ") {
            lines.append("\(indent)\(summary.kind.label): \(summary.sourceName)")
            lines.append("\(indent)  Samples: \(summary.sampleCount)  failures: \(summary.failureCount) (\(Fmt.packetLoss(summary.failureRate)))")
            if let median = summary.median, let p95 = summary.p95 {
                lines.append("\(indent)  Median: \(NetworkMetricDiagnostics.formattedValue(median, unit: summary.unit))  P95: \(NetworkMetricDiagnostics.formattedValue(p95, unit: summary.unit))")
            } else if let latest = summary.latestValue {
                lines.append("\(indent)  Latest: \(NetworkMetricDiagnostics.formattedValue(latest, unit: summary.unit))")
            }
            if let jitter = summary.jitter, summary.unit == .milliseconds {
                lines.append("\(indent)  Jitter: \(NetworkMetricDiagnostics.formattedValue(jitter, unit: summary.unit))")
            }
            if let secondary = summary.secondaryAverage {
                let label = summary.kind == .throughput ? "upload avg" : "secondary avg"
                lines.append("\(indent)  \(label): \(NetworkMetricDiagnostics.formattedValue(secondary, unit: summary.unit))")
            }
            let phaseText = NetworkMetricDiagnostics.applicationPhaseLabels(
                samples: recentNetworkMetricSamples,
                summary: summary
            )
            if !phaseText.isEmpty {
                lines.append("\(indent)  App phases: \(phaseText.joined(separator: "  "))")
            }
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

        if !egressTraceResults.isEmpty {
            lines.append("== Destination Traces ==")
            for result in egressTraceResults {
                let route = result.target.route.label
                lines.append("  \(result.target.displayName) [\(route)]")
                lines.append("    URL: \(result.target.url)")
                if let endpoint = result.endpoint {
                    lines.append("    IP:  \(endpoint.ip)")
                    if let flag = endpoint.flagEmoji, let country = endpoint.countryCode {
                        lines.append("    Country: \(flag) \(country)")
                    }
                    if let colo = endpoint.colo, !colo.isEmpty {
                        lines.append("    CF Colo: \(colo)")
                    }
                    if let warp = endpoint.warpLabel {
                        lines.append("    WARP: \(warp)")
                    }
                    if let gateway = endpoint.gatewayLabel {
                        lines.append("    Gateway: \(gateway)")
                    }
                    if let http = endpoint.httpProtocol, !http.isEmpty {
                        lines.append("    HTTP: \(http)")
                    }
                } else {
                    lines.append("    Error: \(result.error ?? "No response")")
                }
            }
            lines.append("")
        }

        lines.append("== Throughput ==")
        lines.append("  Download: \(Fmt.throughputCompact(downloadBytesPerSec))")
        lines.append("  Upload:   \(Fmt.throughputCompact(uploadBytesPerSec))")
        if let aggregate = recentThroughputAggregate {
            lines.append("  Recent \(aggregate.windowSeconds)s avg: ↓\(Fmt.throughputCompact(aggregate.averageDownload)) ↑\(Fmt.throughputCompact(aggregate.averageUpload))")
            lines.append("  Recent \(aggregate.windowSeconds)s peak: ↓\(Fmt.throughputCompact(aggregate.peakDownload)) ↑\(Fmt.throughputCompact(aggregate.peakUpload))")
        }
        if linkSpeed > 0 { lines.append("  Link:     \(Int(linkSpeed)) Mbps") }
        if !trafficUsageRecords.isEmpty || !trafficUsageBuckets.isEmpty {
            lines.append("  Accumulated by network:")
            for aggregate in trafficUsageAggregates(groupedBy: .network).prefix(5) {
                let marker = aggregate.isCurrent ? " *" : ""
                lines.append("    \(aggregate.displayName)\(marker): ↓\(Fmt.bytes(aggregate.downloadBytes)) ↑\(Fmt.bytes(aggregate.uploadBytes))  total \(Fmt.bytes(aggregate.totalBytes))  (\(aggregate.detail))")
            }
            let ssidAggregates = trafficUsageAggregates(groupedBy: .ssid)
            if !ssidAggregates.isEmpty {
                lines.append("  By SSID:")
                for aggregate in ssidAggregates.prefix(3) {
                    lines.append("    \(aggregate.displayName): ↓\(Fmt.bytes(aggregate.downloadBytes)) ↑\(Fmt.bytes(aggregate.uploadBytes))  total \(Fmt.bytes(aggregate.totalBytes))  (\(aggregate.detail))")
                }
            }
            if !trafficUsageBuckets.isEmpty {
                lines.append("  Detail: \(trafficUsageBuckets.count) daily buckets retained")
                for bucket in trafficUsageBuckets.prefix(5) {
                    lines.append("    \(bucket.day) \(bucket.networkDisplayName): ↓\(Fmt.bytes(bucket.downloadBytes)) ↑\(Fmt.bytes(bucket.uploadBytes))  total \(Fmt.bytes(bucket.totalBytes))")
                }
            }
        }
        lines.append("")

        let recentSummaries = currentNetworkMetricSummaries
        if !recentSummaries.isEmpty {
            lines.append("== Recent Metric Rollups ==")
            lines.append("  Window: recent 15 minutes")
            for summary in recentSummaries.prefix(10) {
                appendMetricSummary(summary)
            }
            lines.append("")
        }

        let metricWindows: [(label: String, seconds: TimeInterval)] = [
            ("15m", 15 * 60),
            ("1h", 60 * 60),
            ("24h", 24 * 60 * 60),
        ]
        let trendRows = metricWindows.compactMap { window -> (String, [NetworkMetricSummary])? in
            let summaries = metricSummaries(window: window.seconds)
                .filter { $0.sampleCount > 0 }
                .prefix(8)
            guard !summaries.isEmpty else { return nil }
            return (window.label, Array(summaries))
        }
        if !trendRows.isEmpty {
            lines.append("== Metric Trend Windows ==")
            for row in trendRows {
                lines.append("  Window: \(row.0)")
                for summary in row.1 {
                    lines.append("    \(NetworkMetricDiagnostics.compactRollupLine(summary))")
                }
            }
            lines.append("")
        }

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

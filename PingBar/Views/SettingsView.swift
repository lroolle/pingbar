import SwiftUI
import ServiceManagement

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case targets
    case egress
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .targets: return "Targets"
        case .egress: return "Public IP"
        case .display: return "Display"
        }
    }

    var detail: String {
        switch self {
        case .general: return "Sampling and startup"
        case .targets: return "ICMP and HTTPS checks"
        case .egress: return "Routes and providers"
        case .display: return "Menu bar"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .targets: return "server.rack"
        case .egress: return "point.3.connected.trianglepath.dotted"
        case .display: return "menubar.rectangle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: NetworkState
    @State private var selectedPane: SettingsPane? = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var pingHosts: [PingHost] = AppConfig.shared.pingHosts
    @State private var proxyProbes: [ProxyProbe] = AppConfig.shared.proxyProbes
    @State private var publicIPProviders: [PublicIPProvider] = AppConfig.shared.publicIPProviders
    @State private var applicationProbes: [ApplicationProbe] = AppConfig.shared.applicationProbes
    @State private var egressTraceTargets: [EgressTraceTarget] = AppConfig.shared.egressTraceTargets
    @State private var panelSections: [PanelSection] = AppConfig.shared.panelSectionOrder
    @State private var newHostAddress = ""
    @State private var newHostLabel = ""
    @State private var newProxyName = ""
    @State private var newProxyKind: ProxyProbeKind = .http
    @State private var newProxyFamily: IPProbeFamily = .automatic
    @State private var newProxyHost = "127.0.0.1"
    @State private var newProxyPort = 7890
    @State private var publicIPFamily = AppConfig.shared.publicIPFamily
    @State private var ipInfoToken = AppConfig.shared.ipInfoToken
    @State private var newProviderName = ""
    @State private var newProviderURL = ""
    @State private var newProviderFamily: IPProbeFamily = .automatic
    @State private var newProviderParser: PublicIPResponseParser = .jsonIP
    @State private var newAppProbeName = ""
    @State private var newAppProbeURL = "https://www.cloudflare.com/cdn-cgi/trace"
    @State private var newAppProbeRoute: ApplicationProbeRoute = .system
    @State private var newTraceName = ""
    @State private var newTraceURL = "https://chatgpt.com/cdn-cgi/trace"
    @State private var newTraceRoute: ApplicationProbeRoute = .system
    @State private var showProviderDetails = false
    @State private var showAddProvider = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(width: 820, height: 600)
    }

    private var settingsSidebar: some View {
        List(SettingsPane.allCases, selection: $selectedPane) { pane in
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .lineLimit(1)
                    Text(pane.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .tag(pane)
        }
        .listStyle(.sidebar)
        .frame(width: 174)
    }

    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader(for: currentPane)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            settingsPane(currentPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var currentPane: SettingsPane {
        selectedPane ?? .general
    }

    private func settingsHeader(for pane: SettingsPane) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(pane.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func settingsPane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            generalTab
        case .targets:
            hostsTab
        case .egress:
            proxiesTab
        case .display:
            displayTab
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: "App", systemImage: "power") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { launchAtLogin = !newValue }
                        }
                    ))
                }

                SettingsSection(title: "Sampling Cadence", systemImage: "timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shorter intervals feel more live but spend more CPU and network budget.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        LabeledContent("ICMP latency") {
                            Picker("", selection: Binding(
                                get: { state.config.pingInterval },
                                set: { state.config.pingInterval = $0; state.restartReaders() }
                            )) {
                                Text("1s").tag(1.0 as TimeInterval)
                                Text("2s").tag(2.0 as TimeInterval)
                                Text("5s").tag(5.0 as TimeInterval)
                                Text("10s").tag(10.0 as TimeInterval)
                            }
                            .frame(width: 120)
                        }

                        LabeledContent("Throughput") {
                            Picker("", selection: Binding(
                                get: { state.config.throughputInterval },
                                set: { state.config.throughputInterval = $0; state.restartReaders() }
                            )) {
                                Text("0.5s").tag(0.5 as TimeInterval)
                                Text("1s").tag(1.0 as TimeInterval)
                                Text("2s").tag(2.0 as TimeInterval)
                            }
                            .frame(width: 120)
                        }

                        LabeledContent("Wi-Fi radio") {
                            Picker("", selection: Binding(
                                get: { state.config.wifiInterval },
                                set: { state.config.wifiInterval = $0; state.restartReaders() }
                            )) {
                                Text("2s").tag(2.0 as TimeInterval)
                                Text("5s").tag(5.0 as TimeInterval)
                                Text("10s").tag(10.0 as TimeInterval)
                                Text("30s").tag(30.0 as TimeInterval)
                            }
                            .frame(width: 120)
                        }

                        LabeledContent("Route evidence") {
                            Picker("", selection: Binding(
                                get: { state.config.networkDetailsInterval },
                                set: { state.config.networkDetailsInterval = $0; state.restartReaders() }
                            )) {
                                Text("5s").tag(5.0 as TimeInterval)
                                Text("10s").tag(10.0 as TimeInterval)
                                Text("30s").tag(30.0 as TimeInterval)
                                Text("60s").tag(60.0 as TimeInterval)
                            }
                            .frame(width: 120)
                        }
                    }
                }

                SettingsSection(title: "Process Traffic", systemImage: "list.bullet.rectangle") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Refresh") {
                            Picker("", selection: Binding(
                                get: { state.config.processStatsInterval },
                                set: { state.config.processStatsInterval = $0; state.restartReaders() }
                            )) {
                                Text("3s").tag(3.0 as TimeInterval)
                                Text("5s").tag(5.0 as TimeInterval)
                                Text("10s").tag(10.0 as TimeInterval)
                                Text("30s").tag(30.0 as TimeInterval)
                            }
                            .frame(width: 120)
                        }

                        LabeledContent("Rows") {
                            Stepper(value: Binding(
                                get: { state.config.topProcessCount },
                                set: {
                                    state.config.topProcessCount = $0
                                    state.readNetworkProcesses()
                                }
                            ), in: 3...10, step: 1) {
                                Text("\(state.config.topProcessCount)")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .frame(width: 120)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var hostsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: "ICMP Targets", systemImage: "dot.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($pingHosts) { $host in
                            HStack {
                                Toggle("", isOn: $host.enabled)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                TextField("Label", text: $host.label)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                TextField("Address", text: $host.address)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                Button(action: { pingHosts.removeAll { $0.id == host.id } }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Address", text: $newHostAddress)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            TextField("Label", text: $newHostLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Button("Add") {
                                let address = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                                let labelText = newHostLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !address.isEmpty, !pingHosts.contains(where: { $0.address == address }) else { return }
                                let label = labelText.isEmpty ? address : labelText
                                pingHosts.append(PingHost(id: UUID().uuidString, address: address, label: label, enabled: true))
                                newHostAddress = ""
                                newHostLabel = ""
                            }
                            .controlSize(.small)
                        }
                    }
                }

                icmpThresholdSection
                httpsThresholdSection
                applicationProbeSection
                egressTraceSection
            }
            .padding(16)
        }
        .onChange(of: pingHosts) { _ in
            let normalized = AppConfig.normalizedPingHosts(pingHosts)
            if normalized != pingHosts {
                pingHosts = normalized
                return
            }
            state.config.pingHosts = normalized
            state.reloadPingHosts()
        }
        .onChange(of: applicationProbes) { _ in
            saveApplicationProbes()
        }
        .onChange(of: egressTraceTargets) { _ in
            saveEgressTraceTargets()
        }
    }

    private var icmpThresholdSection: some View {
        SettingsSection(title: "ICMP Thresholds", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Gateway ICMP is the local link. Public ICMP is the upstream Internet path. Packet loss is shared because any loss is stronger evidence than a slow sample.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 10) {
                    thresholdGroup(
                        title: "Gateway RTT",
                        detail: "router / local link",
                        warning: Binding(
                            get: { state.config.gatewayLatencyCaution },
                            set: { state.config.gatewayLatencyCaution = min($0, state.config.gatewayLatencyCritical); state.refreshWarnings() }
                        ),
                        critical: Binding(
                            get: { state.config.gatewayLatencyCritical },
                            set: { state.config.gatewayLatencyCritical = max($0, state.config.gatewayLatencyCaution); state.refreshWarnings() }
                        ),
                        range: 1...1_000,
                        step: 5
                    )

                    thresholdGroup(
                        title: "Public RTT",
                        detail: "Cloudflare / Google ICMP",
                        warning: Binding(
                            get: { state.config.externalLatencyCaution },
                            set: { state.config.externalLatencyCaution = min($0, state.config.externalLatencyCritical); state.refreshWarnings() }
                        ),
                        critical: Binding(
                            get: { state.config.externalLatencyCritical },
                            set: { state.config.externalLatencyCritical = max($0, state.config.externalLatencyCaution); state.refreshWarnings() }
                        ),
                        range: 1...10_000,
                        step: 10
                    )

                    packetLossThresholdGroup
                }
            }
        } actions: {
            Button(action: resetICMPThresholds) {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var packetLossThresholdGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Packet Loss")
                    .font(.system(size: 11, weight: .semibold))
                Text("recent ICMP failures")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            packetLossStepper("Warn", value: Binding(
                get: { state.config.packetLossCaution },
                set: { state.config.packetLossCaution = min($0, state.config.packetLossCritical); state.refreshWarnings() }
            ))
            packetLossStepper("Critical", value: Binding(
                get: { state.config.packetLossCritical },
                set: { state.config.packetLossCritical = max($0, state.config.packetLossCaution); state.refreshWarnings() }
            ))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }

    private var httpsThresholdSection: some View {
        SettingsSection(title: "HTTPS Probe Thresholds", systemImage: "speedometer") {
            VStack(alignment: .leading, spacing: 10) {
                Text("HTTPS probes include DNS, TCP, TLS, proxy routing, server response, and URLSession overhead. Direct paths should be tighter than system paths that may use a proxy.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 10) {
                    thresholdGroup(
                        title: "Direct HTTPS",
                        detail: "proxy disabled",
                        warning: Binding(
                            get: { state.config.appDirectLatencyCaution },
                            set: { state.config.appDirectLatencyCaution = min($0, state.config.appDirectLatencyCritical); state.refreshWarnings() }
                        ),
                        critical: Binding(
                            get: { state.config.appDirectLatencyCritical },
                            set: { state.config.appDirectLatencyCritical = max($0, state.config.appDirectLatencyCaution); state.refreshWarnings() }
                        )
                    )

                    thresholdGroup(
                        title: "System / Proxy HTTPS",
                        detail: "macOS proxy settings",
                        warning: Binding(
                            get: { state.config.appSystemLatencyCaution },
                            set: { state.config.appSystemLatencyCaution = min($0, state.config.appSystemLatencyCritical); state.refreshWarnings() }
                        ),
                        critical: Binding(
                            get: { state.config.appSystemLatencyCritical },
                            set: { state.config.appSystemLatencyCritical = max($0, state.config.appSystemLatencyCaution); state.refreshWarnings() }
                        )
                    )
                }
            }
        } actions: {
            Button(action: resetHTTPSProbeThresholds) {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private func thresholdGroup(
        title: String,
        detail: String,
        warning: Binding<Double>,
        critical: Binding<Double>,
        range: ClosedRange<Double> = 50...10_000,
        step: Double = 50
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            thresholdStepper("Warn", value: warning, range: range, step: step)
            thresholdStepper("Critical", value: critical, range: range, step: step)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }

    private func thresholdStepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Fmt.latency(value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    private func packetLossStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0.01...1, step: 0.01) {
            HStack {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Fmt.packetLoss(value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    private var applicationProbeSection: some View {
        SettingsSection(title: "Application Probes", systemImage: "timer") {
            VStack(alignment: .leading, spacing: 10) {
                if applicationProbes.isEmpty {
                    Text("No application probes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach($applicationProbes) { $probe in
                            ApplicationProbeEditorRow(
                                probe: $probe,
                                onDelete: { removeApplicationProbe(id: probe.id) }
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    Picker("", selection: $newAppProbeRoute) {
                        ForEach(ApplicationProbeRoute.allCases) { route in
                            Text(route.label).tag(route)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)

                    TextField("Name", text: $newAppProbeName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    TextField("HTTPS URL", text: $newAppProbeURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    Button(action: addApplicationProbe) {
                        Label("Add", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .disabled(!canAddApplicationProbe)
                }
            }
        } actions: {
            Button(action: resetDefaultApplicationProbes) {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var egressTraceSection: some View {
        SettingsSection(title: "App Egress Probes", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                Text("These are app-edge identity probes. They share route semantics with HTTPS app probes, but parse the edge response for the public egress IP.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if egressTraceTargets.isEmpty {
                    Text("No app egress probes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach($egressTraceTargets) { $target in
                            EgressTraceTargetEditorRow(
                                target: $target,
                                onDelete: { removeEgressTraceTarget(id: target.id) }
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    Picker("", selection: $newTraceRoute) {
                        ForEach(ApplicationProbeRoute.allCases) { route in
                            Text(route.label).tag(route)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)

                    TextField("Name", text: $newTraceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    TextField("Edge trace URL", text: $newTraceURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    Button(action: addEgressTraceTarget) {
                        Label("Add", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .disabled(!canAddEgressTraceTarget)
                }
            }
        } actions: {
            Button(action: resetDefaultEgressTraceTargets) {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var proxiesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                publicIPOverviewSection
                customRoutesSection
                ipProviderSection
            }
            .padding(16)
        }
        .onChange(of: proxyProbes) { _ in
            saveProxyProbes()
        }
        .onChange(of: publicIPFamily) { _ in
            savePublicIPFamily()
        }
        .onChange(of: publicIPProviders) { _ in
            savePublicIPProviders()
        }
    }

    private var publicIPOverviewSection: some View {
        SettingsSection(title: "Route Model", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                Text("PingBar compares public identity through a direct URLSession path, the macOS system route, and any explicit local proxy routes you add below.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Address family") {
                    Picker("", selection: $publicIPFamily) {
                        ForEach(IPProbeFamily.allCases) { family in
                            Text(family.detailLabel).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                HStack(spacing: 8) {
                    BuiltInRouteRow(
                        title: "Direct",
                        detail: "URL proxies disabled",
                        value: "Baseline"
                    )
                    BuiltInRouteRow(
                        title: state.proxyStatus.hasConfiguredProxy ? "System Proxy" : "System Route",
                        detail: state.proxyStatus.httpsProbeRoute ?? "macOS network settings",
                        value: state.proxyStatus.hasConfiguredProxy ? "Configured" : "Direct"
                    )
                }
            }
        } actions: {
            Button(action: refreshProxyProbes) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
    }

    private var ipProviderSection: some View {
        SettingsSection(title: "Provider Evidence", systemImage: "building.2.crop.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(providerStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    providerBadge
                }

                HStack(spacing: 8) {
                    TextField("IPinfo token for ASN/location enrichment", text: $ipInfoToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)

                    Button("Save") { applyIPInfoToken() }
                        .controlSize(.small)
                        .disabled(!ipInfoTokenChanged)

                    Button("Clear") { clearIPInfoToken() }
                        .controlSize(.small)
                        .disabled(ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                DisclosureGroup(isExpanded: $showProviderDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($publicIPProviders) { $provider in
                            PublicIPProviderEditorRow(
                                provider: $provider,
                                onDelete: { removePublicIPProvider(id: provider.id) }
                            )
                        }

                        DisclosureGroup(isExpanded: $showAddProvider) {
                            addPublicIPProviderRow
                        } label: {
                            Label("Add Custom Provider", systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Provider endpoints", systemImage: "server.rack")
                        .font(.system(size: 11, weight: .medium))
                }
            }
        } actions: {
            Button(action: resetDefaultPublicIPProviders) {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var addPublicIPProviderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Add provider")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: addPublicIPProvider) {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(!canAddPublicIPProvider)
            }

            HStack(spacing: 8) {
                Picker("", selection: $newProviderFamily) {
                    ForEach(IPProbeFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .labelsHidden()
                .frame(width: 82)

                Picker("", selection: $newProviderParser) {
                    ForEach(PublicIPResponseParser.allCases) { parser in
                        Text(parser.label).tag(parser)
                    }
                }
                .labelsHidden()
                .frame(width: 122)

                TextField("Name", text: $newProviderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)

                TextField("URL", text: $newProviderURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var customRoutesSection: some View {
        SettingsSection(title: "Explicit Route Probes", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(proxyProbes.filter(\.enabled).count) enabled")
                        .font(.system(size: 11, weight: .medium))
                    Text("Optional route checks. A local HTTP or SOCKS proxy is just one route type beside direct and system egress.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }

                if proxyProbes.isEmpty {
                Text("No explicit route probes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach($proxyProbes) { $probe in
                            ProxyProbeEditorRow(
                                probe: $probe,
                                onDelete: { removeProxyProbe(id: probe.id) }
                            )
                        }
                    }
                }

                addProxyProbeRow
            }
        } actions: {
            HStack {
                Button(action: importSystemProxyRoutes) {
                    Label("Import System", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Button(action: resetDefaultProxyProbes) {
                    Label("Defaults", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
        }
    }

    private var addProxyProbeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Add route")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: addProxyProbe) {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(!canAddProxyProbe)
            }

            HStack(spacing: 8) {
                Picker("", selection: $newProxyKind) {
                    ForEach(ProxyProbeKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 96)

                Picker("", selection: $newProxyFamily) {
                    ForEach(IPProbeFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .labelsHidden()
                .frame(width: 84)

                TextField("Name", text: $newProxyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)

                TextField("Host", text: $newProxyHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 150)

                TextField("Port", value: $newProxyPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 74)

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var displayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                menuBarLayoutSection
                if state.config.menuBarContentMode != .speed {
                    menuBarIdentitySection
                }
                menuBarWidthSection
                panelLayoutSection
            }
            .padding(16)
        }
        .onAppear {
            panelSections = state.config.panelSectionOrder
        }
        .onChange(of: panelSections) { newValue in
            state.config.panelSectionOrder = newValue
            state.objectWillChange.send()
        }
    }

    private var menuBarLayoutSection: some View {
        SettingsSection(title: "Menu Bar", systemImage: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Content", selection: Binding(
                    get: { state.config.menuBarContentMode },
                    set: applyMenuBarContentMode
                )) {
                    ForEach(MenuBarContentMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Style", selection: Binding(
                    get: { state.config.menuBarStyle },
                    set: applyMenuBarStyle
                )) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 18) {
                    Toggle("Health indicator", isOn: Binding(
                        get: { state.config.showHealthDot },
                        set: { state.config.showHealthDot = $0; state.objectWillChange.send() }
                    ))

                    Toggle("Upload speed", isOn: Binding(
                        get: { state.config.showUploadInMenuBar },
                        set: { state.config.showUploadInMenuBar = $0; state.objectWillChange.send() }
                    ))
                    .disabled(state.config.menuBarContentMode == .egress)
                }

                menuBarSlotControls
                menuBarPreview
            }
        }
    }

    @ViewBuilder
    private var menuBarSlotControls: some View {
        switch state.config.menuBarContentMode {
        case .speed:
            menuBarSpeedSlotSummary
        case .egress:
            menuBarEgressSlotPicker
        case .hybrid:
            HStack(alignment: .top, spacing: 14) {
                menuBarSpeedSlotSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 64)

                menuBarEgressSlotPicker
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var menuBarSpeedSlotSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Speed slot", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
            Text(state.config.showUploadInMenuBar ? "Upload and download rates" : "Download rate only")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var menuBarEgressSlotPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Egress identity slot", systemImage: "globe")
                .font(.system(size: 11, weight: .semibold))

            if menuBarEgressSourceOptions.isEmpty {
                Text("Route evidence is still loading.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Show", selection: Binding(
                    get: { selectedMenuBarEgressSourceID },
                    set: selectMenuBarEgressSource
                )) {
                    ForEach(menuBarEgressSourceOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)

                if let option = selectedMenuBarEgressSource {
                    Text(option.detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var menuBarIdentitySection: some View {
        SettingsSection(title: "Identity Details", systemImage: "globe") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    traceToggle("Mask IP", \.menuBarTraceMaskIP)
                    traceToggle("Target name", \.menuBarTraceShowDestination)
                }
                GridRow {
                    traceToggle("Compact", \.menuBarTraceCompact)
                    traceToggle("Country flag", \.menuBarTraceShowFlag)
                }
                GridRow {
                    traceToggle("Country code", \.menuBarTraceShowCountryCode)
                    traceToggle("Cloudflare colo", \.menuBarTraceShowColo)
                }
                GridRow {
                    traceToggle("WARP", \.menuBarTraceShowWarp)
                    traceToggle("Gateway", \.menuBarTraceShowGateway)
                }
                GridRow {
                    traceToggle("HTTP protocol", \.menuBarTraceShowHTTP)
                    Color.clear.frame(height: 1)
                }
            }
        }
    }

    private var menuBarWidthSection: some View {
        SettingsSection(title: "Width", systemImage: "arrow.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                if state.config.menuBarStyle == .stacked {
                    widthPresetRow(stackedWidthPresets)
                    widthStepper(title: "Stacked width", range: stackedWidthRange)
                } else if state.config.menuBarContentMode == .speed {
                    Toggle("Fixed speed width", isOn: Binding(
                        get: { state.config.menuBarFixedWidth },
                        set: { state.config.menuBarFixedWidth = $0; state.objectWillChange.send() }
                    ))

                    if state.config.menuBarFixedWidth {
                        widthPresetRow([
                            WidthPreset(title: "Compact", value: 108),
                            WidthPreset(title: "Balanced", value: 136),
                            WidthPreset(title: "Roomy", value: 164),
                        ])
                        widthStepper(title: "Fixed width", range: 88...220)
                    } else {
                        widthModeRow("Automatic", detail: "speed readout sizes to its content")
                    }
                } else {
                    widthModeRow("Automatic", detail: "identity text sizes to its current route label")
                    Button(action: { applyMenuBarStyle(.stacked) }) {
                        Label("Use Stacked Fixed Layout", systemImage: "rectangle.split.2x1")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var panelLayoutSection: some View {
        SettingsSection(title: "Panel Order", systemImage: "rectangle.3.group") {
            VStack(alignment: .leading, spacing: 10) {
                List {
                    ForEach(panelSections) { panelSection in
                        PanelSectionOrderRow(section: panelSection)
                    }
                    .onMove(perform: movePanelSections)
                }
                .listStyle(.inset)
                .frame(height: CGFloat(panelSections.count * 38 + 8))
                .clipShape(RoundedRectangle(cornerRadius: 7))

                HStack(spacing: 8) {
                    Text("Warnings stay pinned above the ordered sections.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: resetPanelSectionOrder) {
                        Label("Default Order", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var menuBarPreview: some View {
        HStack(spacing: 8) {
            if state.config.showHealthDot {
                Circle()
                    .fill(previewHealthColor)
                    .frame(width: 7, height: 7)
            }

            if state.config.menuBarStyle == .stacked, state.config.menuBarContentMode == .hybrid {
                HStack(spacing: 8) {
                    Text(menuBarPreviewLines.first ?? "")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: 58, alignment: .leading)

                    Divider()
                        .frame(height: 18)

                    Text(menuBarPreviewLines.dropFirst().first ?? "")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else if state.config.menuBarStyle == .stacked {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(menuBarPreviewLines.prefix(2), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            } else if state.config.menuBarStyle == .iconOnly {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text(menuBarPreviewText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(7)
    }

    private var currentMenuBarWidth: Double {
        if state.config.menuBarStyle == .stacked {
            let minimum = state.config.menuBarContentMode == .hybrid ? 184.0 : 96.0
            return max(state.config.stackedMenuBarWidth, minimum)
        }
        return state.config.menuBarWidth
    }

    private func setCurrentMenuBarWidth(_ width: Double) {
        if state.config.menuBarStyle == .stacked {
            state.config.stackedMenuBarWidth = width
        } else {
            state.config.menuBarWidth = width
        }
        state.objectWillChange.send()
    }

    private func applyMenuBarContentMode(_ mode: MenuBarContentMode) {
        state.config.menuBarContentMode = mode
        normalizeMenuBarWidthPolicy()
        state.objectWillChange.send()
    }

    private func applyMenuBarStyle(_ style: MenuBarStyle) {
        state.config.menuBarStyle = style
        normalizeMenuBarWidthPolicy()
        state.objectWillChange.send()
    }

    private func normalizeMenuBarWidthPolicy() {
        guard state.config.menuBarContentMode != .speed else { return }
        state.config.menuBarFixedWidth = false
        let minimumStackedWidth = state.config.menuBarContentMode == .hybrid ? 184.0 : 136.0
        if state.config.menuBarStyle == .stacked, state.config.stackedMenuBarWidth < minimumStackedWidth {
            state.config.stackedMenuBarWidth = minimumStackedWidth
        }
    }

    private var menuBarEgressSourceOptions: [EgressSourceOption] {
        var options = state.egressRoutes.map { route in
            EgressSourceOption(
                id: "route:\(route.id)",
                title: route.label,
                detail: route.detail ?? "route probe"
            )
        }

        let traceOptions = egressTraceTargets
            .filter(\.enabled)
            .map { target in
                EgressSourceOption(
                    id: "trace:\(target.id)",
                    title: target.displayName,
                    detail: "\(target.route.label) app edge · \(traceTargetHost(target))"
                )
            }
        options.append(contentsOf: traceOptions)

        if options.isEmpty {
            options = [
                EgressSourceOption(id: "route:no-url-proxy", title: "Direct Probe", detail: "URL proxy disabled"),
                EgressSourceOption(id: "route:system-settings", title: "System Route", detail: "macOS network settings"),
            ]
        }
        return options
    }

    private var selectedMenuBarEgressSourceID: String {
        let options = menuBarEgressSourceOptions
        if options.contains(where: { $0.id == state.config.menuBarEgressSourceID }) {
            return state.config.menuBarEgressSourceID
        }
        if let selectedTrace = egressTraceTargets.first(where: { $0.enabled && $0.showInMenuBar }) {
            return "trace:\(selectedTrace.id)"
        }
        return options.first?.id ?? ""
    }

    private var selectedMenuBarEgressSource: EgressSourceOption? {
        let id = selectedMenuBarEgressSourceID
        return menuBarEgressSourceOptions.first { $0.id == id }
    }

    private func selectMenuBarEgressSource(_ id: String) {
        guard !id.isEmpty else { return }
        state.config.menuBarEgressSourceID = id
        for index in egressTraceTargets.indices {
            let traceID = "trace:\(egressTraceTargets[index].id)"
            egressTraceTargets[index].showInMenuBar = traceID == id
            if traceID == id {
                egressTraceTargets[index].enabled = true
            }
        }
        saveEgressTraceTargets()
    }

    private func traceTargetHost(_ target: EgressTraceTarget) -> String {
        URL(string: target.url)?.host ?? target.url
    }

    private func traceToggle(_ title: String, _ keyPath: ReferenceWritableKeyPath<AppConfig, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { state.config[keyPath: keyPath] },
            set: {
                state.config[keyPath: keyPath] = $0
                state.objectWillChange.send()
            }
        ))
        .frame(width: 190, alignment: .leading)
    }

    private func widthPresetRow(_ presets: [WidthPreset]) -> some View {
        HStack(spacing: 8) {
            ForEach(presets) { preset in
                Button(preset.title) {
                    setCurrentMenuBarWidth(preset.value)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
    }

    private var stackedWidthPresets: [WidthPreset] {
        if state.config.menuBarContentMode == .hybrid {
            return [
                WidthPreset(title: "Compact", value: 184),
                WidthPreset(title: "Balanced", value: 204),
                WidthPreset(title: "Roomy", value: 224),
            ]
        }

        return [
            WidthPreset(title: "Compact", value: 112),
            WidthPreset(title: "Balanced", value: 136),
            WidthPreset(title: "Roomy", value: 164),
        ]
    }

    private var stackedWidthRange: ClosedRange<Double> {
        state.config.menuBarContentMode == .hybrid ? 184...240 : 96...220
    }

    private func widthStepper(title: String, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Stepper(value: Binding(
                get: { currentMenuBarWidth },
                set: { setCurrentMenuBarWidth($0) }
            ), in: range, step: 4) {
                Text("\(Int(currentMenuBarWidth)) pt")
                    .font(.system(size: 11, design: .monospaced))
            }
        }
    }

    private func widthModeRow(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func movePanelSections(from source: IndexSet, to destination: Int) {
        panelSections.move(fromOffsets: source, toOffset: destination)
    }

    private func resetPanelSectionOrder() {
        panelSections = AppConfig.defaultPanelSectionOrder
    }

    private var previewHealthColor: Color {
        switch state.health {
        case .good: return .green
        case .degraded: return .yellow
        case .poor: return .red
        case .unknown: return .secondary
        }
    }

    private var menuBarPreviewLines: [String] {
        switch state.config.menuBarContentMode {
        case .speed:
            return [
                "↑ \(speedPreviewValue(state.uploadBytesPerSec))",
                "↓ \(speedPreviewValue(state.downloadBytesPerSec))",
            ]
        case .egress:
            return previewEgressLines
        case .hybrid:
            return [
                "↓ \(speedPreviewValue(state.downloadBytesPerSec))",
                previewEgressLines.first ?? "@ Egress --",
            ]
        }
    }

    private var menuBarPreviewText: String {
        let text: String
        switch state.config.menuBarContentMode {
        case .speed:
            if state.config.showUploadInMenuBar {
                text = "↑\(speedPreviewValue(state.uploadBytesPerSec)) ↓\(speedPreviewValue(state.downloadBytesPerSec))"
            } else {
                text = "↓\(speedPreviewValue(state.downloadBytesPerSec))"
            }
        case .egress:
            text = previewEgressText(compact: state.config.menuBarStyle != .detailed)
        case .hybrid:
            text = "↓\(speedPreviewValue(state.downloadBytesPerSec)) \(previewEgressText(compact: true))"
        }

        guard text.count > 30 else { return text }
        return "\(text.prefix(29))…"
    }

    private var previewEgressLines: [String] {
        guard let identity = previewSelectedEgressIdentity else {
            return ["@ Egress --", "IP --"]
        }
        return [
            "@ \(previewEgressTop(identity))",
            "\(previewIPFamilySymbol(identity.endpoint?.ip)) \(previewEgressBottom(identity, compact: true))",
        ]
    }

    private func previewEgressText(compact: Bool) -> String {
        guard let identity = previewSelectedEgressIdentity else { return "Egress --" }
        return "\(previewEgressTop(identity)) \(previewEgressBottom(identity, compact: compact))"
    }

    private var previewSelectedEgressIdentity: EgressPreviewIdentity? {
        let identities = previewEgressIdentities
        if let selected = identities.first(where: { $0.id == selectedMenuBarEgressSourceID }) {
            return selected
        }
        return identities.first
    }

    private var previewEgressIdentities: [EgressPreviewIdentity] {
        let routeIdentities = state.egressRoutes.map { route in
            EgressPreviewIdentity(
                id: "route:\(route.id)",
                label: route.label,
                detail: route.detail ?? "route probe",
                endpoint: route.endpoint
            )
        }

        let resultsByID = state.egressTraceResults.reduce(into: [String: EgressTraceResult]()) { results, result in
            results[result.id] = result
        }
        let traceIdentities = egressTraceTargets.filter(\.enabled).map { target in
            EgressPreviewIdentity(
                id: "trace:\(target.id)",
                label: target.displayName,
                detail: "\(target.route.label) app edge",
                endpoint: resultsByID[target.id]?.endpoint
            )
        }

        return routeIdentities + traceIdentities
    }

    private func previewEgressTop(_ identity: EgressPreviewIdentity) -> String {
        guard let endpoint = identity.endpoint else { return "\(shortPreviewName(identity.label)) --" }
        var parts: [String] = []
        if state.config.menuBarTraceShowDestination {
            parts.append(shortPreviewName(identity.label))
        }
        if state.config.menuBarTraceShowFlag, let flag = endpoint.flagEmoji {
            parts.append(flag)
        }
        if state.config.menuBarTraceShowCountryCode, let country = endpoint.countryCode {
            parts.append(country)
        }
        if state.config.menuBarTraceShowColo, let colo = endpoint.colo, !colo.isEmpty {
            parts.append(colo)
        }
        return parts.isEmpty ? shortPreviewName(identity.label) : parts.joined(separator: " ")
    }

    private func previewEgressBottom(_ identity: EgressPreviewIdentity, compact: Bool) -> String {
        guard let endpoint = identity.endpoint else { return identity.detail }
        var parts = [
            previewDisplayIP(endpoint.ip, masked: state.config.menuBarTraceMaskIP, compact: compact || state.config.menuBarTraceCompact)
        ]
        if state.config.menuBarTraceShowWarp, let warp = endpoint.warp, warp == "on" || warp == "plus" {
            parts.append(warp == "plus" ? "WARP+" : "WARP")
        }
        if !compact || !state.config.menuBarTraceCompact {
            if state.config.menuBarTraceShowGateway, let gateway = endpoint.gatewayLabel {
                parts.append(gateway)
            }
            if state.config.menuBarTraceShowHTTP, let http = endpoint.httpProtocol, !http.isEmpty {
                parts.append(http)
            }
        }
        return parts.joined(separator: " ")
    }

    private func previewIPFamilySymbol(_ ip: String?) -> String {
        guard let ip else { return "IP" }
        return ip.contains(":") ? "v6" : "v4"
    }

    private var previewTraceSlots: [(target: EgressTraceTarget, result: EgressTraceResult?)] {
        let enabledTargets = state.config.egressTraceTargets.filter(\.enabled)
        var targets = enabledTargets.filter(\.showInMenuBar)
        if targets.isEmpty {
            targets = Array(enabledTargets.prefix(1))
        }
        if targets.isEmpty {
            targets = Array(AppConfig.defaultEgressTraceTargets.prefix(1))
        }
        targets = Array(targets.prefix(1))

        let resultsByID = state.egressTraceResults.reduce(into: [String: EgressTraceResult]()) { results, result in
            results[result.id] = result
        }
        return targets.map { target in (target, resultsByID[target.id]) }
    }

    private func previewTraceText(
        slot: (target: EgressTraceTarget, result: EgressTraceResult?)?,
        compact: Bool
    ) -> String {
        guard let slot else { return "Trace --" }
        guard let endpoint = slot.result?.endpoint else {
            return "\(shortPreviewName(slot.target.displayName)) --"
        }

        var parts: [String] = []
        if state.config.menuBarTraceShowDestination {
            parts.append(shortPreviewName(slot.target.displayName))
        }
        if state.config.menuBarTraceShowFlag, let flag = endpoint.flagEmoji {
            parts.append(flag)
        }
        if state.config.menuBarTraceShowCountryCode, let country = endpoint.countryCode {
            parts.append(country)
        }
        parts.append(previewDisplayIP(endpoint.ip, masked: state.config.menuBarTraceMaskIP, compact: compact || state.config.menuBarTraceCompact))
        if state.config.menuBarTraceShowColo, let colo = endpoint.colo, !colo.isEmpty {
            parts.append(compact ? colo : "CF \(colo)")
        }
        if state.config.menuBarTraceShowWarp, let warp = endpoint.warp, warp == "on" || warp == "plus" {
            parts.append(warp == "plus" ? "WARP+" : "WARP")
        }
        if !compact || !state.config.menuBarTraceCompact {
            parts.append(slot.target.route.label)
            if state.config.menuBarTraceShowGateway, let gateway = endpoint.gatewayLabel {
                parts.append(gateway)
            }
            if state.config.menuBarTraceShowHTTP, let http = endpoint.httpProtocol, !http.isEmpty {
                parts.append(http)
            }
        }
        return parts.joined(separator: " ")
    }

    private func speedPreviewValue(_ bytes: Int64) -> String {
        let (value, unit) = Fmt.bytesPerSec(bytes)
        return "\(value)\(unit)"
    }

    private func shortPreviewName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: " Trace", with: "")
            .replacingOccurrences(of: " Direct", with: "D")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 10 else { return cleaned }
        return String(cleaned.prefix(10))
    }

    private func previewDisplayIP(_ ip: String, masked: Bool, compact: Bool) -> String {
        if masked {
            if ip.contains(":") {
                let parts = ip.split(separator: ":", omittingEmptySubsequences: false).filter { !$0.isEmpty }
                guard !parts.isEmpty else { return "IPv6 ..." }
                return "\(parts.prefix(2).joined(separator: ":")):..."
            }

            let parts = ip.split(separator: ".").map(String.init)
            guard parts.count == 4 else { return "IP ..." }
            return "\(parts[0]).\(parts[1]).x.x"
        }

        guard compact, ip.contains(":") else { return ip }
        let parts = ip.split(separator: ":", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        guard let first = parts.first, let last = parts.last, first != last else { return ip }
        return "\(first):...\(last)"
    }

    private var canAddProxyProbe: Bool {
        let host = newProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty && (1...65535).contains(newProxyPort)
    }

    private var canAddPublicIPProvider: Bool {
        let name = newProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newProviderURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && URL(string: url)?.scheme?.hasPrefix("http") == true
    }

    private var canAddApplicationProbe: Bool {
        let url = newAppProbeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: url)?.scheme?.hasPrefix("http") == true
    }

    private var canAddEgressTraceTarget: Bool {
        let url = newTraceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: url)?.scheme?.hasPrefix("http") == true
    }

    private var providerStatus: String {
        let enabledCount = publicIPProviders.filter(\.enabled).count
        let tokenProviders = publicIPProviders.filter { $0.enabled && $0.requiresIPInfoToken }.count
        if tokenProviders > 0, ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(enabledCount) providers enabled; IPinfo endpoints need a token"
        }
        return "\(enabledCount) providers enabled"
    }

    private var providerBadge: some View {
        Text(ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Off" : "Configured")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
    }

    private var ipInfoTokenChanged: Bool {
        ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines) != state.config.ipInfoToken
    }

    private func savePublicIPFamily() {
        state.config.publicIPFamily = publicIPFamily
        state.refreshPublicIPs()
    }

    private func savePublicIPProviders() {
        state.config.publicIPProviders = normalizedPublicIPProviders(publicIPProviders)
        state.refreshPublicIPs()
    }

    private func resetDefaultPublicIPProviders() {
        publicIPProviders = AppConfig.defaultPublicIPProviders
        state.config.publicIPProviders = publicIPProviders
        state.refreshPublicIPs()
    }

    private func removePublicIPProvider(id: String) {
        publicIPProviders.removeAll { $0.id == id }
        state.config.publicIPProviders = normalizedPublicIPProviders(publicIPProviders)
        state.refreshPublicIPs()
    }

    private func addPublicIPProvider() {
        let name = newProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newProviderURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, URL(string: url)?.scheme?.hasPrefix("http") == true else { return }

        publicIPProviders.append(PublicIPProvider(
            name: name,
            url: url,
            family: newProviderFamily,
            parser: newProviderParser,
            enabled: true,
            requiresIPInfoToken: url.contains("{ipinfoToken}")
        ))
        publicIPProviders = normalizedPublicIPProviders(publicIPProviders)
        state.config.publicIPProviders = publicIPProviders
        newProviderName = ""
        newProviderURL = ""
        state.refreshPublicIPs()
    }

    private func applyIPInfoToken() {
        state.config.ipInfoToken = ipInfoToken.trimmingCharacters(in: .whitespacesAndNewlines)
        state.refreshPublicIPs()
    }

    private func clearIPInfoToken() {
        ipInfoToken = ""
        state.config.ipInfoToken = ""
        state.refreshPublicIPs()
    }

    private func saveProxyProbes() {
        state.config.proxyProbes = normalizedProxyProbes(proxyProbes)
        state.refreshPublicIPs()
    }

    private func saveApplicationProbes() {
        state.config.applicationProbes = normalizedApplicationProbes(applicationProbes)
        state.reloadApplicationProbes()
    }

    private func saveEgressTraceTargets() {
        let normalized = normalizedEgressTraceTargets(egressTraceTargets)
        if normalized != egressTraceTargets {
            egressTraceTargets = normalized
        }
        state.config.egressTraceTargets = normalized
        state.reloadEgressTraceTargets()
        state.objectWillChange.send()
    }

    private func resetDefaultApplicationProbes() {
        applicationProbes = AppConfig.defaultApplicationProbes
        state.config.applicationProbes = applicationProbes
        state.reloadApplicationProbes()
    }

    private func resetDefaultEgressTraceTargets() {
        egressTraceTargets = AppConfig.defaultEgressTraceTargets
        saveEgressTraceTargets()
    }

    private func resetICMPThresholds() {
        state.config.resetICMPThresholds()
        state.refreshWarnings()
        state.objectWillChange.send()
    }

    private func resetHTTPSProbeThresholds() {
        state.config.resetApplicationLatencyThresholds()
        state.refreshWarnings()
        state.objectWillChange.send()
    }

    private func removeApplicationProbe(id: String) {
        applicationProbes.removeAll { $0.id == id }
        state.config.applicationProbes = normalizedApplicationProbes(applicationProbes)
        state.reloadApplicationProbes()
    }

    private func removeEgressTraceTarget(id: String) {
        egressTraceTargets.removeAll { $0.id == id }
        saveEgressTraceTargets()
    }

    private func addApplicationProbe() {
        let url = newAppProbeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: url)?.scheme?.hasPrefix("http") == true else { return }

        let name = newAppProbeName.trimmingCharacters(in: .whitespacesAndNewlines)
        applicationProbes.append(ApplicationProbe(
            name: name.isEmpty ? URL(string: url)?.host ?? url : name,
            url: url,
            route: newAppProbeRoute,
            enabled: true
        ))
        applicationProbes = normalizedApplicationProbes(applicationProbes)
        state.config.applicationProbes = applicationProbes
        newAppProbeName = ""
        state.reloadApplicationProbes()
    }

    private func addEgressTraceTarget() {
        let url = newTraceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: url)?.scheme?.hasPrefix("http") == true else { return }

        let name = newTraceName.trimmingCharacters(in: .whitespacesAndNewlines)
        egressTraceTargets.append(EgressTraceTarget(
            name: name.isEmpty ? URL(string: url)?.host ?? url : name,
            url: url,
            route: newTraceRoute,
            parser: .cloudflareTrace,
            enabled: true,
            showInMenuBar: egressTraceTargets.filter(\.showInMenuBar).count < 2
        ))
        newTraceName = ""
        saveEgressTraceTargets()
    }

    private func refreshProxyProbes() {
        proxyProbes = normalizedProxyProbes(proxyProbes)
        state.config.proxyProbes = proxyProbes
        state.refreshPublicIPs()
    }

    private func resetDefaultProxyProbes() {
        proxyProbes = AppConfig.defaultProxyProbes
        state.config.proxyProbes = proxyProbes
        state.refreshPublicIPs()
    }

    private func importSystemProxyRoutes() {
        let status = ProxyReader().read()
        var imported = proxyProbes

        appendProxy(status.httpProxy, kind: .http, prefix: "System HTTP", to: &imported)
        appendProxy(status.httpsProxy, kind: .http, prefix: "System HTTPS", to: &imported)
        appendProxy(status.socksProxy, kind: .socks5, prefix: "System SOCKS", to: &imported)

        proxyProbes = normalizedProxyProbes(imported)
        state.config.proxyProbes = proxyProbes
        state.refreshPublicIPs()
    }

    private func appendProxy(
        _ endpoint: String?,
        kind: ProxyProbeKind,
        prefix: String,
        to probes: inout [ProxyProbe]
    ) {
        guard let endpoint,
              let parts = parseProxyEndpoint(endpoint)
        else { return }

        guard !probes.contains(where: { $0.kind == kind && $0.host == parts.host && $0.port == parts.port }) else {
            return
        }

        probes.append(ProxyProbe(
            name: "\(prefix) \(parts.host):\(parts.port)",
            kind: kind,
            host: parts.host,
            port: parts.port,
            enabled: true
        ))
    }

    private func parseProxyEndpoint(_ endpoint: String) -> (host: String, port: Int)? {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("["),
           let close = value.firstIndex(of: "]") {
            let host = String(value[value.index(after: value.startIndex)..<close])
            let portStart = value.index(after: close)
            guard portStart < value.endIndex,
                  value[portStart] == ":",
                  let port = Int(value[value.index(after: portStart)...])
            else { return nil }
            return (host, port)
        }

        guard let separator = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: separator)...])
        else { return nil }

        let host = String(value[..<separator])
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    private func removeProxyProbe(id: String) {
        proxyProbes.removeAll { $0.id == id }
        state.config.proxyProbes = normalizedProxyProbes(proxyProbes)
        state.refreshPublicIPs()
    }

    private func addProxyProbe() {
        let host = newProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = newProxyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(newProxyPort) else { return }

        let probe = ProxyProbe(
            name: name.isEmpty ? "\(newProxyKind.label) \(host):\(newProxyPort)" : name,
            kind: newProxyKind,
            host: host,
            port: newProxyPort,
            enabled: true,
            ipFamily: newProxyFamily
        )
        proxyProbes = normalizedProxyProbes(proxyProbes + [probe])
        state.config.proxyProbes = proxyProbes
        newProxyName = ""
        state.refreshPublicIPs()
    }

    private func normalizedProxyProbes(_ probes: [ProxyProbe]) -> [ProxyProbe] {
        probes.map { probe in
            var copy = probe
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.host = copy.host.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.port = min(max(copy.port, 1), 65535)
            return copy
        }
    }

    private func normalizedPublicIPProviders(_ providers: [PublicIPProvider]) -> [PublicIPProvider] {
        PublicIPProviderCatalog.normalized(providers.map { provider in
            var copy = provider
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.url = copy.url.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.requiresIPInfoToken = copy.requiresIPInfoToken || copy.url.contains("{ipinfoToken}")
            return copy
        })
    }

    private func normalizedApplicationProbes(_ probes: [ApplicationProbe]) -> [ApplicationProbe] {
        probes.map { probe in
            var copy = probe
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.url = copy.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if copy.name.isEmpty {
                copy.name = URL(string: copy.url)?.host ?? copy.url
            }
            return copy
        }
    }

    private func normalizedEgressTraceTargets(_ targets: [EgressTraceTarget]) -> [EgressTraceTarget] {
        var normalized = targets.map { target in
            var copy = target
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.url = copy.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if copy.name.isEmpty {
                copy.name = URL(string: copy.url)?.host ?? copy.url
            }
            return copy
        }

        let selectedIDs = normalized
            .filter { $0.enabled && $0.showInMenuBar }
            .map(\.id)

        if state.config.menuBarEgressSourceID.hasPrefix("route:") {
            for index in normalized.indices {
                normalized[index].showInMenuBar = false
            }
            return normalized
        }

        if let selectedID = selectedIDs.first {
            for index in normalized.indices {
                normalized[index].showInMenuBar = normalized[index].id == selectedID
            }
        } else if let firstEnabled = normalized.firstIndex(where: \.enabled) {
            normalized[firstEnabled].showInMenuBar = true
        }

        return normalized
    }
}

private struct WidthPreset: Identifiable {
    let title: String
    let value: Double

    var id: String { title }
}

private struct EgressSourceOption: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct EgressPreviewIdentity {
    let id: String
    let label: String
    let detail: String
    let endpoint: PublicEndpointInfo?
}

private struct PanelSectionOrderRow: View {
    let section: PanelSection

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 14)

            Image(systemName: section.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.label)
                    .font(.system(size: 11, weight: .semibold))
                Text(section.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsSection<Content: View, Actions: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    let actions: Actions

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                actions
            }
            content
        }
        .padding(12)
        .background(Color.secondary.opacity(0.055))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private extension SettingsSection where Actions == EmptyView {
    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.actions = EmptyView()
    }
}

private struct BuiltInRouteRow: View {
    let title: String
    let detail: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

private struct PublicIPProviderEditorRow: View {
    @Binding var provider: PublicIPProvider
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: $provider.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Provider", text: $provider.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Picker("", selection: $provider.family) {
                    ForEach(IPProbeFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .labelsHidden()
                .frame(width: 82)

                Picker("", selection: $provider.parser) {
                    ForEach(PublicIPResponseParser.allCases) { parser in
                        Text(parser.label).tag(parser)
                    }
                }
                .labelsHidden()
                .frame(width: 126)

                Toggle("Diag", isOn: $provider.diagnostic)
                    .font(.system(size: 10))

                Toggle("Token", isOn: $provider.requiresIPInfoToken)
                    .font(.system(size: 10))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            TextField("URL", text: $provider.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .padding(.leading, 22)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

private struct ApplicationProbeEditorRow: View {
    @Binding var probe: ApplicationProbe
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: $probe.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Name", text: $probe.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Picker("", selection: $probe.route) {
                    ForEach(ApplicationProbeRoute.allCases) { route in
                        Text(route.label).tag(route)
                    }
                }
                .labelsHidden()
                .frame(width: 92)

                Text(probe.route.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            TextField("HTTPS URL", text: $probe.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .padding(.leading, 22)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

private struct EgressTraceTargetEditorRow: View {
    @Binding var target: EgressTraceTarget
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: $target.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Name", text: $target.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Picker("", selection: $target.route) {
                    ForEach(ApplicationProbeRoute.allCases) { route in
                        Text(route.label).tag(route)
                    }
                }
                .labelsHidden()
                .frame(width: 92)

                if target.showInMenuBar {
                    Text("Menu bar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.10))
                        .cornerRadius(5)
                }

                Text(target.route.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            TextField("Edge trace URL", text: $target.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .padding(.leading, 22)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

private struct ProxyProbeEditorRow: View {
    @Binding var probe: ProxyProbe
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: $probe.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Route name", text: $probe.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150)

                Picker("", selection: $probe.kind) {
                    ForEach(ProxyProbeKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 96)

                Picker("", selection: $probe.ipFamily) {
                    ForEach(IPProbeFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .labelsHidden()
                .frame(width: 82)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Text("Endpoint")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 58, alignment: .leading)

                TextField("Host", text: $probe.host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 150)

                Text(":")
                    .foregroundColor(.secondary)

                TextField("Port", value: $probe.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 74)
            }
            .padding(.leading, 22)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

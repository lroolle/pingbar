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
        case .egress: return "Egress"
        case .display: return "Display"
        }
    }

    var detail: String {
        switch self {
        case .general: return "Sampling and startup"
        case .targets: return "Latency hosts"
        case .egress: return "Public IP probes"
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

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(width: 780, height: 540)
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
        Form {
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

            LabeledContent("Ping interval") {
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

            LabeledContent("Throughput interval") {
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

            LabeledContent("Wi-Fi interval") {
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

            LabeledContent("Network interval") {
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

            LabeledContent("Process interval") {
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

            LabeledContent("Top processes") {
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
        .padding()
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
                                pingHosts.append(PingHost(address: address, label: label, enabled: true))
                                newHostAddress = ""
                                newHostLabel = ""
                            }
                            .controlSize(.small)
                        }
                    }
                }

                applicationProbeSection
            }
            .padding(16)
        }
        .onChange(of: pingHosts) { _ in
            state.config.pingHosts = pingHosts
            state.reloadPingHosts()
        }
        .onChange(of: applicationProbes) { _ in
            saveApplicationProbes()
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

    private var proxiesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                egressEvidenceSection
                ipProviderSection
                customRoutesSection
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

    private var egressEvidenceSection: some View {
        SettingsSection(title: "Egress Evidence", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Address family") {
                    Picker("", selection: $publicIPFamily) {
                        ForEach(IPProbeFamily.allCases) { family in
                            Text(family.detailLabel).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                VStack(spacing: 6) {
                    BuiltInRouteRow(
                        title: "Direct",
                        detail: "URL proxy disabled",
                        value: "Always probed"
                    )
                    BuiltInRouteRow(
                        title: state.proxyStatus.hasConfiguredProxy ? "System Proxy" : "System Route",
                        detail: state.proxyStatus.httpsProbeRoute ?? "macOS network settings",
                        value: state.proxyStatus.hasConfiguredProxy ? "Active" : "Direct"
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
        SettingsSection(title: "IP Probe Providers", systemImage: "building.2.crop.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(providerStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    providerBadge
                }

                HStack(spacing: 8) {
                    TextField("Optional IPinfo API token", text: $ipInfoToken)
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

                VStack(spacing: 8) {
                    ForEach($publicIPProviders) { $provider in
                        PublicIPProviderEditorRow(
                            provider: $provider,
                            onDelete: { removePublicIPProvider(id: provider.id) }
                        )
                    }
                }

                addPublicIPProviderRow
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
        SettingsSection(title: "Custom Proxy Routes", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 10) {
                if proxyProbes.isEmpty {
                    Text("No custom routes")
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
        Form {
            Picker("Menu bar style", selection: Binding(
                get: { state.config.menuBarStyle },
                set: { state.config.menuBarStyle = $0; state.objectWillChange.send() }
            )) {
                ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
            }

            Toggle("Show health indicator", isOn: Binding(
                get: { state.config.showHealthDot },
                set: { state.config.showHealthDot = $0; state.objectWillChange.send() }
            ))

            Toggle("Show upload speed", isOn: Binding(
                get: { state.config.showUploadInMenuBar },
                set: { state.config.showUploadInMenuBar = $0; state.objectWillChange.send() }
            ))

            Toggle("Fixed menu bar width", isOn: Binding(
                get: { state.config.menuBarFixedWidth },
                set: { state.config.menuBarFixedWidth = $0; state.objectWillChange.send() }
            ))

            LabeledContent("Menu bar width") {
                Stepper(value: Binding(
                    get: { currentMenuBarWidth },
                    set: { setCurrentMenuBarWidth($0) }
                ), in: 88...180, step: 4) {
                    Text("\(Int(currentMenuBarWidth)) pt")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .padding()
    }

    private var currentMenuBarWidth: Double {
        if state.config.menuBarStyle == .stacked {
            return state.config.stackedMenuBarWidth
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
    }

    private func saveApplicationProbes() {
        state.config.applicationProbes = normalizedApplicationProbes(applicationProbes)
        state.reloadApplicationProbes()
    }

    private func resetDefaultApplicationProbes() {
        applicationProbes = AppConfig.defaultApplicationProbes
        state.config.applicationProbes = applicationProbes
        state.reloadApplicationProbes()
    }

    private func removeApplicationProbe(id: String) {
        applicationProbes.removeAll { $0.id == id }
        state.config.applicationProbes = normalizedApplicationProbes(applicationProbes)
        state.reloadApplicationProbes()
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .cornerRadius(7)
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .cornerRadius(8)
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .cornerRadius(8)
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .cornerRadius(8)
    }
}

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: NetworkState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var pingHosts: [PingHost] = AppConfig.shared.pingHosts
    @State private var newHostAddress = ""
    @State private var newHostLabel = ""

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            hostsTab.tabItem { Label("Hosts", systemImage: "server.rack") }
            displayTab.tabItem { Label("Display", systemImage: "menubar.rectangle") }
        }
        .frame(width: 440, height: 320)
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
        }
        .padding()
    }

    private var hostsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach($pingHosts) { $host in
                    HStack {
                        Toggle("", isOn: $host.enabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        Text(host.label)
                            .frame(width: 80, alignment: .leading)
                        Text(host.address)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { pingHosts.removeAll { $0.id == host.id } }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 160)

            HStack(spacing: 8) {
                TextField("Address", text: $newHostAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField("Label", text: $newHostLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Button("Add") {
                    guard !newHostAddress.isEmpty else { return }
                    let label = newHostLabel.isEmpty ? newHostAddress : newHostLabel
                    pingHosts.append(PingHost(address: newHostAddress, label: label, enabled: true))
                    newHostAddress = ""
                    newHostLabel = ""
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .onChange(of: pingHosts) { _ in
            AppConfig.shared.pingHosts = pingHosts
        }
    }

    private var displayTab: some View {
        Form {
            Picker("Menu bar style", selection: Binding(
                get: { state.config.menuBarStyle },
                set: { state.config.menuBarStyle = $0 }
            )) {
                ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
            }

            Toggle("Show health indicator", isOn: Binding(
                get: { state.config.showHealthDot },
                set: { state.config.showHealthDot = $0 }
            ))

            Toggle("Show upload speed", isOn: Binding(
                get: { state.config.showUploadInMenuBar },
                set: { state.config.showUploadInMenuBar = $0 }
            ))
        }
        .padding()
    }
}

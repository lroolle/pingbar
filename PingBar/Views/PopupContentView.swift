import SwiftUI

struct PopupContentView: View {
    @EnvironmentObject var state: NetworkState
    @State private var copiedReport = false

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(
                copiedReport: copiedReport,
                copyAction: copyDiagnostic,
                pinAction: detachWindow,
                settingsAction: openSettings
            )
            .environmentObject(state)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !state.activeWarnings.isEmpty {
                        WarningBanner(
                            warnings: state.activeWarnings,
                            clearAction: { state.clearWarnings() }
                        )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }

                    ForEach(visiblePanelSections) { panelSection in
                        section { panelSectionView(panelSection) }
                        if panelSection.id != visiblePanelSections.last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .onAppear { state.loadSpeedTestHistory() }
    }

    private var visiblePanelSections: [PanelSection] {
        state.config.panelSectionOrder.filter { panelSection in
            switch panelSection {
            case .speedHistory:
                return !state.speedTestHistory.isEmpty
            default:
                return true
            }
        }
    }

    @ViewBuilder
    private func panelSectionView(_ panelSection: PanelSection) -> some View {
        switch panelSection {
        case .latency:
            PingSection()
        case .metricRollups:
            NetworkMetricsSection()
        case .throughput:
            ThroughputSection()
        case .trafficUsage:
            TrafficUsageSection()
        case .egress:
            ProxySection()
        case .wifi:
            WiFiSection()
        case .processes:
            NetworkProcessesSection()
        case .speedTest:
            SpeedTestSection()
        case .speedHistory:
            if !state.speedTestHistory.isEmpty {
                SpeedTestHistorySection()
            }
        }
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .environmentObject(state)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func copyDiagnostic() {
        let report = state.diagnosticReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        withAnimation(.easeInOut(duration: 0.18)) { copiedReport = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.18)) { copiedReport = false }
        }
    }

    private func detachWindow() {
        AppDelegate.shared?.popover.performClose(nil)
        FloatingWindowController.shared.show(state: state)
    }

    private func openSettings() {
        AppDelegate.shared?.popover.performClose(nil)
        AppDelegate.shared?.showSettingsWindow()
    }
}

struct StatusHeader: View {
    @EnvironmentObject var state: NetworkState
    let copiedReport: Bool
    let copyAction: () -> Void
    let pinAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(healthColor.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(healthColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("PingBar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.health.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                headerButton(
                    copiedReport ? "Copied" : "Copy Report",
                    systemImage: copiedReport ? "checkmark" : "doc.on.clipboard",
                    color: copiedReport ? .green : .secondary,
                    action: copyAction
                )

                headerButton("Pin", systemImage: "pin", action: pinAction)
                headerButton("Settings", systemImage: "gearshape", action: settingsAction)

                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 8) {
                if let wifi = state.wifiInfo, let ssid = wifi.ssid {
                    headerPill(ssid, systemImage: "wifi")
                }
                if let iface = state.cachedInterfaceLabel ?? state.cachedInterface {
                    headerPill(iface, systemImage: "network")
                }
                if let location = headerLocation {
                    headerPill(location, systemImage: "globe")
                }
                if let warp = state.directEndpoint?.warpLabel, warp != "WARP off" {
                    headerPill(warp, systemImage: "shield")
                }
            }
        }
    }

    private func headerButton(
        _ title: String,
        systemImage: String,
        color: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundColor(color)
        .help(title)
    }

    private func headerPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(5)
    }

    private var healthColor: Color {
        switch state.health {
        case .good:     return .green
        case .degraded: return .yellow
        case .poor:     return .red
        case .unknown:  return .gray
        }
    }

    private var headerLocation: String? {
        guard let endpoint = state.directEndpoint else { return nil }
        let label = endpoint.colo ?? endpoint.countryCode
        guard let label, !label.isEmpty else { return nil }
        if let flag = endpoint.flagEmoji {
            return "\(flag) \(label)"
        }
        return label
    }
}

private extension Color {
    static var quaternaryLabelColor: Color {
        Color(nsColor: .quaternaryLabelColor)
    }
}

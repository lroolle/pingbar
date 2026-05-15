import SwiftUI

struct PopupContentView: View {
    @EnvironmentObject var state: NetworkState
    @State private var copiedReport = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                StatusHeader()
                    .environmentObject(state)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if !state.activeWarnings.isEmpty {
                    WarningBanner(
                        warnings: state.activeWarnings,
                        clearAction: { state.clearWarnings() }
                    )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                Divider().padding(.horizontal, 16)
                section { ThroughputSection() }
                Divider().padding(.horizontal, 16)
                section { PingSection() }
                Divider().padding(.horizontal, 16)
                section { WiFiSection() }
                Divider().padding(.horizontal, 16)
                section { ProxySection() }
                Divider().padding(.horizontal, 16)
                section { SpeedTestSection() }

                if !state.speedTestHistory.isEmpty {
                    Divider().padding(.horizontal, 16)
                    section { SpeedTestHistorySection() }
                }

                Divider().padding(.horizontal, 16)
                section { NetworkProcessesSection() }

                footer
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .onAppear { state.loadSpeedTestHistory() }
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .environmentObject(state)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: copyDiagnostic) {
                HStack(spacing: 3) {
                    Image(systemName: copiedReport ? "checkmark" : "doc.on.clipboard")
                    Text(copiedReport ? "Copied" : "Copy Report")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(copiedReport ? .green : .secondary)

            Button(action: detachWindow) {
                HStack(spacing: 3) {
                    Image(systemName: "pin")
                    Text("Pin")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: openSettings) {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Text("PingBar")
                .font(.system(size: 9))
                .foregroundColor(.quaternaryLabelColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

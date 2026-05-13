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
                    WarningBanner(warnings: state.activeWarnings)
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

                footer
            }
        }
        .frame(width: 320)
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
        withAnimation(.snappy) { copiedReport = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.snappy) { copiedReport = false }
        }
    }

    private func detachWindow() {
        AppDelegate.shared?.popover.performClose(nil)
        FloatingWindowController.shared.show(state: state)
    }
}

struct StatusHeader: View {
    @EnvironmentObject var state: NetworkState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(healthColor)
                .frame(width: 10, height: 10)

            Text(state.health.label)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let wifi = state.wifiInfo, let ssid = wifi.ssid {
                Label(ssid, systemImage: "wifi")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var healthColor: Color {
        switch state.health {
        case .good:     return .green
        case .degraded: return .yellow
        case .poor:     return .red
        case .unknown:  return .gray
        }
    }
}

private extension Color {
    static var quaternaryLabelColor: Color {
        Color(nsColor: .quaternaryLabelColor)
    }
}

import SwiftUI

struct PopupContentView: View {
    @EnvironmentObject var state: NetworkState

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

                footer
            }
        }
        .frame(width: 320)
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .environmentObject(state)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("PingBar")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

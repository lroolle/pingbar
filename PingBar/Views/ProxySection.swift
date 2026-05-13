import SwiftUI

struct ProxySection: View {
    @EnvironmentObject var state: NetworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Network")
                Spacer()
                Button(action: { state.refreshPublicIPs() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                GridRow {
                    Text("Proxy").modifier(InfoLabel())
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.proxyStatus.isActive ? Color.blue : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(state.proxyStatus.summary)
                            .modifier(InfoValue())
                    }
                }

                if let ip = state.directIP {
                    ipRow("Direct IP", ip)
                }

                if let ip = state.proxyIP, ip != state.directIP {
                    ipRow("Proxy IP", ip)
                }
            }
        }
    }

    private func ipRow(_ label: String, _ ip: String) -> some View {
        GridRow {
            Text(label).modifier(InfoLabel())
            Text(ip)
                .modifier(InfoValue())
                .textSelection(.enabled)
        }
    }
}

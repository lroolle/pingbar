import SwiftUI

struct PingSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var expandedHost: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Latency")

            ForEach(state.allPingHostOrder, id: \.self) { host in
                if let ping = state.pingResults[host] {
                    VStack(spacing: 2) {
                        pingRow(host: host, result: ping)

                        if expandedHost == host,
                           let history = state.latencyHistory[host],
                           history.count >= 4 {
                            Sparkline(
                                values: history.values,
                                color: statusColor(ping),
                                height: 24
                            )
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(3)
                            .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private func pingRow(host: String, result: PingResult) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(statusColor(result))
                .frame(width: 6, height: 6)
                .padding(.trailing, 6)

            Text(result.label)
                .font(.system(size: 11))
                .frame(width: 70, alignment: .leading)

            Spacer()

            Text(Fmt.latency(result.latencyMs))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 65, alignment: .trailing)

            if let jitter = result.jitterMs, jitter > 0.5 {
                Text("±\(String(format: "%.0f", jitter))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            } else {
                Spacer().frame(width: 30)
            }

            if result.packetLoss > 0 {
                Text(Fmt.packetLoss(result.packetLoss))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(width: 35, alignment: .trailing)
            } else {
                Spacer().frame(width: 35)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                expandedHost = expandedHost == host ? nil : host
            }
        }
    }

    private func statusColor(_ result: PingResult) -> Color {
        if !result.isReachable { return .red }
        guard let ms = result.latencyMs else { return .gray }
        if ms < 20 { return .green }
        if ms < 50 { return .yellow }
        return .orange
    }
}

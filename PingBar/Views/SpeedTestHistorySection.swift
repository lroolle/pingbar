import SwiftUI

struct SpeedTestHistorySection: View {
    @EnvironmentObject var state: NetworkState
    @State private var expanded = false

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.speedTestHistory.prefix(5)) { entry in
                    historyRow(entry)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                SectionHeader("Speed Test Log", systemImage: "clock")
                Spacer()
                if let latest = state.speedTestHistory.first {
                    Text("last \(timeFormatter.string(from: latest.date))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func historyRow(_ entry: SpeedTestHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(timeFormatter.string(from: entry.date))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)

                if let ssid = entry.wifiSSID, !ssid.isEmpty {
                    Label(ssid, systemImage: "wifi")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !entry.server.isEmpty {
                    Text(entry.server)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if entry.downloadBps > 0 {
                    Text("↓\(Fmt.bitsPerSec(entry.downloadBps))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                }

                if entry.uploadBps > 0 {
                    Text("↑\(Fmt.bitsPerSec(entry.uploadBps))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 6) {
                if !entry.server.isEmpty {
                    Text(entry.server)
                }
                if let rssi = entry.wifiRSSI {
                    Text("\(rssi)dBm")
                }
                if let snr = entry.wifiSNR {
                    Text("SNR \(snr)")
                }
                if let channel = entry.wifiChannel {
                    Text("Ch \(channel)")
                }
                if entry.noProxy {
                    Text("No URL")
                } else if let proxyIP = entry.proxyIP, proxyIP != entry.directIP {
                    Text("System")
                }
                if let warp = entry.directWarp, warp != "off" {
                    Text("WARP \(warp)")
                } else if let warp = entry.proxyWarp, warp != "off" {
                    Text("WARP \(warp)")
                }
            }
            .font(.system(size: 8.5))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }
}

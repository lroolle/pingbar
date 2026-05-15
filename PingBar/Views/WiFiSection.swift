import SwiftUI

struct WiFiSection: View {
    @EnvironmentObject var state: NetworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader("Wi-Fi", systemImage: "wifi")
                Spacer()
                Button(action: { SystemSettings.openWiFi() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            if let wifi = state.wifiInfo {
                wifiGrid(wifi)
            } else {
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func wifiGrid(_ wifi: WiFiInfo) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            if let ssid = wifi.ssid {
                infoRow("SSID", ssid)
            }
            if let ch = wifi.channel, let band = wifi.channelBand, let width = wifi.channelWidth {
                infoRow("Channel", "\(ch) · \(band) · \(width)")
            }
            if let phy = wifi.phyMode {
                infoRow("Standard", phy)
            }
            if let rssi = wifi.rssi {
                GridRow {
                    Text("Signal").modifier(InfoLabel())
                    HStack(spacing: 6) {
                        Text("\(rssi) dBm")
                            .modifier(InfoValue())
                        signalBars(rssi: rssi)
                        if let snr = wifi.snr {
                            Text("SNR \(snr) dB")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            if let rate = wifi.transmitRate, rate > 0 {
                infoRow("Tx Rate", "\(Int(rate)) Mbps")
            }
            if let sec = wifi.security, sec != "unknown" {
                infoRow("Security", sec)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).modifier(InfoLabel())
            Text(value).modifier(InfoValue())
        }
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barFill(index: i, rssi: rssi))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }

    private func barFill(index: Int, rssi: Int) -> Color {
        let thresholds = [-80, -70, -60, -50]
        guard rssi >= thresholds[index] else { return Color.primary.opacity(0.12) }
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        return .orange
    }
}

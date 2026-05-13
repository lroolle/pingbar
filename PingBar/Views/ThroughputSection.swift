import SwiftUI

struct ThroughputSection: View {
    @EnvironmentObject var state: NetworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Throughput")
                Spacer()
                if state.linkSpeed > 0 {
                    Text("Link \(Int(state.linkSpeed)) Mbps")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                speedColumn(direction: "↑", bytes: state.uploadBytesPerSec, color: .blue)
                speedColumn(direction: "↓", bytes: state.downloadBytesPerSec, color: .green)
                Spacer()
            }

            if state.downloadHistory.count >= 4 {
                DualSparkline(
                    uploadValues: state.uploadHistory.values,
                    downloadValues: state.downloadHistory.values,
                    height: 32
                )
                .background(Color.primary.opacity(0.02))
                .cornerRadius(4)
            }
        }
    }

    private func speedColumn(direction: String, bytes: Int64, color: Color) -> some View {
        let (val, unit) = Fmt.bytesPerSec(bytes)
        return HStack(spacing: 3) {
            Text(direction)
                .foregroundColor(color)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(val)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .offset(y: 2)
        }
    }
}

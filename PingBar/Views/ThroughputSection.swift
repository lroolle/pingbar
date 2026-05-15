import SwiftUI

struct ThroughputSection: View {
    @EnvironmentObject var state: NetworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader("Throughput", systemImage: "arrow.up.arrow.down")
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
                ThroughputGraph(
                    uploadValues: state.uploadHistory.values,
                    downloadValues: state.downloadHistory.values,
                    height: 62
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.10), lineWidth: 0.5)
                )
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

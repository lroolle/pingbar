import SwiftUI

struct NetworkProcessesSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 4) {
                if state.topNetworkProcesses.isEmpty {
                    emptyRow
                } else {
                    ForEach(state.topNetworkProcesses) { process in
                        processRow(process)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                SectionHeader("Top Processes", systemImage: "list.bullet.rectangle")
                Spacer()
                Button(action: { state.readNetworkProcesses() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .disclosureGroupStyle(.automatic)
    }

    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text("Collecting process traffic")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func processRow(_ process: NetworkProcessSample) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: process.icon)
                .resizable()
                .frame(width: 16, height: 16)
                .cornerRadius(3)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("pid \(process.pid)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                processRate("↓", process.downloadBytesPerSec, .green)
                processRate("↑", process.uploadBytesPerSec, .blue)
            }
        }
        .padding(.vertical, 2)
    }

    private func processRate(_ symbol: String, _ bytes: Int64, _ color: Color) -> some View {
        let formatted = Fmt.bytesPerSec(bytes)
        return HStack(spacing: 2) {
            Text(symbol)
                .foregroundColor(color)
            Text(formatted.value)
            Text(formatted.unit)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 9.5, design: .monospaced))
        .frame(width: 76, alignment: .trailing)
    }
}

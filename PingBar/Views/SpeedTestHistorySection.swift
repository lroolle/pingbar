import SwiftUI

struct SpeedTestHistorySection: View {
    @EnvironmentObject var state: NetworkState

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("History")

            ForEach(state.speedTestHistory.prefix(5)) { entry in
                historyRow(entry)
            }
        }
    }

    private func historyRow(_ entry: SpeedTestHistoryEntry) -> some View {
        HStack(spacing: 8) {
            Text(timeFormatter.string(from: entry.date))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .leading)

            if !entry.server.isEmpty {
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
    }
}

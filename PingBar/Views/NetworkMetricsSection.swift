import SwiftUI

struct NetworkMetricsSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader("Metric Rollups", systemImage: "chart.xyaxis.line")
                Spacer()
                if !visibleSummaries.isEmpty {
                    Text("15m")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if visibleSummaries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(visibleSummaries) { summary in
                        NetworkMetricSummaryRow(
                            summary: summary,
                            severityPolicy: severityPolicy
                        )
                    }

                    if hiddenCount > 0 || (showAll && sortedSummaries.count > compactLimit) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showAll.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showAll ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(showAll ? "Show fewer metrics" : "Show \(hiddenCount) more metrics")
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var compactLimit: Int { 3 }

    private var severityPolicy: NetworkMetricSeverityPolicy {
        NetworkMetricSeverityPolicy(config: state.config)
    }

    private var visibleSummaries: [NetworkMetricSummary] {
        let prioritized = sortedSummaries
        if showAll { return prioritized }
        return Array(prioritized.prefix(compactLimit))
    }

    private var hiddenCount: Int {
        max(0, sortedSummaries.count - visibleSummaries.count)
    }

    private var sortedSummaries: [NetworkMetricSummary] {
        state.currentNetworkMetricSummaries.sorted {
            let lhsSeverity = severityScore($0)
            let rhsSeverity = severityScore($1)
            if lhsSeverity != rhsSeverity {
                return lhsSeverity > rhsSeverity
            }
            let lhsScore = priority($0)
            let rhsScore = priority($1)
            if lhsScore == rhsScore {
                return $0.sourceName < $1.sourceName
            }
            return lhsScore > rhsScore
        }
    }

    private func priority(_ summary: NetworkMetricSummary) -> Int {
        switch summary.kind {
        case .gatewayLatency: return 100
        case .externalLatency: return 90
        case .applicationLatency: return 80
        case .wifiSignal: return 70
        case .throughput: return 60
        case .applicationPhaseLatency: return 55
        case .speedTestLatency, .speedTestDownload, .speedTestUpload: return 50
        }
    }

    private func severityScore(_ summary: NetworkMetricSummary) -> Int {
        switch NetworkMetricDiagnostics.rollupSeverityBand(for: summary, policy: severityPolicy) {
        case .critical: return 3
        case .caution: return 2
        case .good: return 1
        case .neutral: return 0
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Collecting time-based evidence")
                    .font(.system(size: 11, weight: .medium))
                Text("Rollups appear after latency, app path, throughput, or Wi-Fi samples arrive.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
    }
}

private struct NetworkMetricSummaryRow: View {
    let summary: NetworkMetricSummary
    let severityPolicy: NetworkMetricSeverityPolicy

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor.opacity(0.85))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(summary.sourceName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text(kindLabel)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text("n=\(summary.sampleCount)")
                    if summary.failureCount > 0 {
                        Text("\(Fmt.packetLoss(summary.failureRate)) fail")
                            .foregroundColor(.red)
                    }
                    if let route = summary.route {
                        Text(route)
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(primaryMetricText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                if let secondaryMetricText {
                    Text(secondaryMetricText)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(statusColor.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch NetworkMetricDiagnostics.rollupSeverityBand(
            for: summary,
            policy: severityPolicy
        ) {
        case .good: return .green
        case .caution: return .orange
        case .critical: return .red
        case .neutral: return .secondary
        }
    }

    private var shouldShowJitter: Bool {
        summary.unit == .milliseconds && summary.jitter != nil
    }

    private var kindLabel: String {
        switch summary.kind {
        case .gatewayLatency: return "gateway"
        case .externalLatency: return "external"
        case .applicationLatency: return "app"
        case .applicationPhaseLatency:
            return summary.sourceID.split(separator: ":").last.map(String.init) ?? "phase"
        case .throughput: return "traffic"
        case .wifiSignal: return "wifi"
        case .speedTestLatency: return "speed ping"
        case .speedTestDownload: return "download"
        case .speedTestUpload: return "upload"
        }
    }

    private var primaryMetricText: String {
        if let p95 = summary.p95 {
            return "p95 \(formatValue(p95))"
        }
        if let median = summary.median {
            return "p50 \(formatValue(median))"
        }
        if let latest = summary.latestValue {
            return "now \(formatValue(latest))"
        }
        return "--"
    }

    private var secondaryMetricText: String? {
        if let median = summary.median, summary.p95 != nil {
            return "p50 \(formatValue(median))"
        }
        if shouldShowJitter, let jitter = summary.jitter {
            return "jit \(formatValue(jitter))"
        }
        if let secondary = summary.secondaryAverage {
            let label = summary.kind == .throughput ? "up" : "2nd"
            return "\(label) \(formatValue(secondary))"
        }
        return nil
    }

    private func formatValue(_ value: Double) -> String {
        NetworkMetricDiagnostics.formattedValue(value, unit: summary.unit)
    }
}

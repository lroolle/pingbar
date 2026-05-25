import SwiftUI

struct PingSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var showAllTargets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                SectionHeader("Latency", systemImage: "waveform.path.ecg")
                Spacer()
                if !displayRows.isEmpty {
                    Text("\(reachableCount)/\(displayRows.count) up")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(reachableCount == displayRows.count ? .secondary : .orange)
                }
            }

            if latencySeries.count >= 1 {
                MultiLatencyGraph(series: latencySeries, height: 62)
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

            if !displayRows.isEmpty {
                summaryStrip
            }

            if !state.applicationProbeResults.isEmpty {
                applicationProbeStrip
            }

            VStack(spacing: 2) {
                ForEach(visibleRows) { row in
                    pingRow(row)
                }

                if hiddenTargetCount > 0 || (showAllTargets && displayRows.count > compactLimit) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showAllTargets.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showAllTargets ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                            Text(showAllTargets ? "Show fewer targets" : "Show \(hiddenTargetCount) more targets")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var latencySeries: [LatencySeries] {
        Array(state.allPingHostOrder.enumerated()).compactMap { index, host in
            guard let history = state.latencySampleHistory[host], history.count >= 2 else { return nil }
            let label = state.pingResults[host]?.label ?? host
            let thresholds = latencyThresholds(for: host)
            return LatencySeries(
                id: host,
                label: label,
                samples: history.values,
                color: color(for: index),
                warningMs: thresholds.warning,
                criticalMs: thresholds.critical
            )
        }
    }

    private var displayRows: [LatencyTargetRow] {
        Array(state.allPingHostOrder.enumerated()).compactMap { index, host in
            guard let result = state.pingResults[host] else { return nil }
            return LatencyTargetRow(
                id: host,
                order: index,
                result: result,
                color: color(for: index),
                isProblem: isProblem(result)
            )
        }
    }

    private var visibleRows: [LatencyTargetRow] {
        guard !showAllTargets, displayRows.count > compactLimit else { return displayRows }

        var selected: [LatencyTargetRow] = []
        var ids = Set<String>()

        func append(_ row: LatencyTargetRow) {
            guard !ids.contains(row.id) else { return }
            selected.append(row)
            ids.insert(row.id)
        }

        if let gateway = displayRows.first(where: { $0.result.host == state.cachedGateway }) {
            append(gateway)
        }

        for row in displayRows where row.isProblem {
            append(row)
        }

        for row in displayRows where selected.count < compactLimit {
            append(row)
        }

        return selected.sorted { $0.order < $1.order }
    }

    private var hiddenTargetCount: Int {
        max(0, displayRows.count - visibleRows.count)
    }

    private var reachableCount: Int {
        displayRows.filter { $0.result.isReachable }.count
    }

    private var lossCount: Int {
        displayRows.filter { $0.result.packetLoss > 0 }.count
    }

    private var slowestLatency: Double? {
        displayRows.compactMap(\.result.latencyMs).max()
    }

    private var compactLimit: Int { 5 }

    private var summaryStrip: some View {
        HStack(spacing: 5) {
            metricPill("\(displayRows.count) targets")
            if let slowestLatency {
                metricPill("max \(Fmt.latency(slowestLatency))", color: slowestLatency >= 100 ? .orange : .secondary)
            }
            if lossCount > 0 {
                metricPill("\(lossCount) loss", color: .red)
            }
            if displayRows.count > compactLimit, !showAllTargets {
                metricPill("compact", color: .secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func metricPill(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)
    }

    private var applicationProbeStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Application path")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 5) {
                ForEach(state.applicationProbeResults.prefix(3)) { result in
                    applicationProbePill(result)
                }
                if state.applicationProbeResults.count > 3 {
                    metricPill("+\(state.applicationProbeResults.count - 3)", color: .secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func applicationProbePill(_ result: ApplicationProbeResult) -> some View {
        let color = applicationProbeColor(result)
        let latency = result.durationMs.map { Fmt.latency($0) } ?? "--"
        return Text("\(result.probe.route.label) \(result.probe.name) \(latency)")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.08))
            .cornerRadius(4)
    }

    private func applicationProbeColor(_ result: ApplicationProbeResult) -> Color {
        if let summary = applicationSummary(for: result) {
            switch NetworkMetricDiagnostics.rollupSeverityBand(
                for: summary,
                policy: NetworkMetricSeverityPolicy(config: state.config)
            ) {
            case .critical:
                return .red
            case .caution:
                return .orange
            case .good, .neutral:
                return .secondary
            }
        }

        if !result.isHealthy {
            return .orange
        }

        if let duration = result.durationMs {
            let thresholds = applicationProbeThresholds(for: result.probe.route)
            if duration >= thresholds.critical { return .red }
            if duration >= thresholds.warning { return .orange }
        }
        return .secondary
    }

    private func applicationSummary(for result: ApplicationProbeResult) -> NetworkMetricSummary? {
        state.currentNetworkMetricSummaries.first {
            $0.kind == .applicationLatency && $0.sourceID == result.id
        }
    }

    private func applicationProbeThresholds(for route: ApplicationProbeRoute) -> (warning: Double, critical: Double) {
        switch route {
        case .direct:
            return (state.config.appDirectLatencyCaution, state.config.appDirectLatencyCritical)
        case .system:
            return (state.config.appSystemLatencyCaution, state.config.appSystemLatencyCritical)
        }
    }

    private func pingRow(_ row: LatencyTargetRow) -> some View {
        let result = row.result
        return HStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(row.color.opacity(0.32))
                    .frame(width: 14, height: 2)
                Circle()
                    .fill(row.isProblem ? severityColor(result) : row.color)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 16, height: 8)
            .padding(.trailing, 6)

            Text(result.label)
                .font(.system(size: 11, weight: result.host == state.cachedGateway ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 70, alignment: .leading)

            Spacer()

            Text(Fmt.latency(result.latencyMs))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(row.isProblem ? severityColor(result) : .primary)
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
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(row.isProblem ? severityColor(result).opacity(0.07) : Color.clear)
        .cornerRadius(4)
    }

    private func color(for index: Int) -> Color {
        let colors: [Color] = [.blue, .cyan, .indigo, .purple, .teal, .mint]
        return colors[index % colors.count]
    }

    private func isProblem(_ result: PingResult) -> Bool {
        if isGateway(result), result.sent > 0 && !result.isReachable { return true }
        if hasPacketLossProblem(result) { return true }
        let thresholds = latencyThresholds(for: result.host)
        return (result.latencyMs ?? result.averageMs ?? 0) >= thresholds.warning
    }

    private func severityColor(_ result: PingResult) -> Color {
        if isGateway(result) {
            if result.sent > 0 && !result.isReachable { return .red }
            if result.packetLoss >= state.config.packetLossCritical { return .red }
            if result.packetLoss >= state.config.packetLossCaution { return .orange }
        } else {
            if result.recentLossCount >= 3 && result.packetLoss >= state.config.packetLossCritical { return .red }
            if hasPacketLossProblem(result) { return .orange }
        }
        let latency = result.latencyMs ?? result.averageMs ?? 0
        let thresholds = latencyThresholds(for: result.host)
        return latency >= thresholds.critical ? .red : .orange
    }

    private func hasPacketLossProblem(_ result: PingResult) -> Bool {
        if isGateway(result) {
            return result.packetLoss >= state.config.packetLossCaution
        }
        return result.recentLossCount >= 2
            && result.recentSampleCount >= 10
            && result.packetLoss >= state.config.packetLossCaution
    }

    private func isGateway(_ result: PingResult) -> Bool {
        result.host == state.cachedGateway
    }

    private func latencyThresholds(for host: String) -> (warning: Double, critical: Double) {
        if host == state.cachedGateway {
            return (state.config.gatewayLatencyCaution, state.config.gatewayLatencyCritical)
        }
        return (state.config.externalLatencyCaution, state.config.externalLatencyCritical)
    }
}

private struct LatencyTargetRow: Identifiable {
    let id: String
    let order: Int
    let result: PingResult
    let color: Color
    let isProblem: Bool
}

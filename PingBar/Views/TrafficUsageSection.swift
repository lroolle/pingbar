import SwiftUI

struct TrafficUsageSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var aggregation: NetworkTrafficAggregation = .network
    @State private var showInactive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionHeader("Traffic Usage", systemImage: "chart.bar.xaxis")
                Spacer()
                if !state.trafficUsageRecords.isEmpty || !state.trafficUsageBuckets.isEmpty {
                    Picker("", selection: $aggregation) {
                        ForEach(NetworkTrafficAggregation.allCases) { aggregation in
                            Text(aggregation.label).tag(aggregation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 156)

                    Button(action: { state.clearTrafficUsage() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Clear traffic usage history")
                }
            }

            if visibleAggregates.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(visibleAggregates) { aggregate in
                        TrafficUsageRow(aggregate: aggregate)
                    }

                    if !inactiveAggregates.isEmpty {
                        inactiveDisclosure
                    }

                    if showInactive {
                        ForEach(expandedInactiveAggregates) { aggregate in
                            TrafficUsageRow(aggregate: aggregate)
                        }

                        if hiddenInactiveCount > 0 {
                            Text("\(hiddenInactiveCount) more inactive \(inactiveGroupLabel(for: hiddenInactiveCount)) kept in history")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9)
                        }
                    }
                }
            }
        }
        .onChange(of: aggregation) { _ in
            showInactive = false
        }
    }

    private var allAggregates: [NetworkTrafficAggregate] {
        state.trafficUsageAggregates(groupedBy: aggregation)
    }

    private var visibleAggregates: [NetworkTrafficAggregate] {
        let live = allAggregates.filter(\.isCurrent)
        if !live.isEmpty { return live }
        return Array(allAggregates.prefix(1))
    }

    private var inactiveAggregates: [NetworkTrafficAggregate] {
        let visibleIDs = Set(visibleAggregates.map(\.id))
        return allAggregates.filter { !visibleIDs.contains($0.id) }
    }

    private var expandedInactiveAggregates: [NetworkTrafficAggregate] {
        Array(inactiveAggregates.prefix(4))
    }

    private var hiddenInactiveCount: Int {
        max(0, inactiveAggregates.count - expandedInactiveAggregates.count)
    }

    private func inactiveGroupLabel(for count: Int) -> String {
        switch aggregation {
        case .network:
            return count == 1 ? "network" : "networks"
        case .ssid:
            return "SSIDs"
        case .interface:
            return count == 1 ? "interface" : "interfaces"
        }
    }

    private var inactiveDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showInactive.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showInactive ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                Text("\(inactiveAggregates.count) inactive \(inactiveGroupLabel(for: inactiveAggregates.count))")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(showInactive ? "Hide" : "Show")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(Color.primary.opacity(0.018))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Collecting local interface counters")
                    .font(.system(size: 11, weight: .medium))
                Text("Totals start after the first throughput baseline for this SSID or interface.")
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

private struct TrafficUsageRow: View {
    let aggregate: NetworkTrafficAggregate

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(aggregate.isCurrent ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(aggregate.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if aggregate.isCurrent {
                        Text("live")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.10))
                            .cornerRadius(4)
                    }
                }

                Text("\(aggregate.detail) · last \(relativeDate(aggregate.lastSeen))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    trafficMetric("Down", aggregate.downloadBytes, color: .green)
                    trafficMetric("Up", aggregate.uploadBytes, color: .blue)
                }
                Text("Total \(Fmt.bytes(aggregate.totalBytes))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(Color.primary.opacity(aggregate.isCurrent ? 0.045 : 0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(aggregate.isCurrent ? Color.green.opacity(0.18) : Color.secondary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func trafficMetric(_ label: String, _ bytes: Int64, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.secondary)
            Text(Fmt.bytes(bytes))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

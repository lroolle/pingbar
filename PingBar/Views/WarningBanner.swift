import SwiftUI

struct WarningBanner: View {
    let warnings: [Warning]
    let clearAction: () -> Void
    @State private var expanded = false

    private var visibleWarnings: [Warning] {
        expanded ? warnings : Array(warnings.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: iconName(worstSeverity))
                    .foregroundColor(iconColor(worstSeverity))
                    .font(.system(size: 10))
                    .frame(width: 14)

                Text(summaryText)
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                Button(disclosureTitle) {
                    withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

                Button(action: clearAction) {
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            ForEach(visibleWarnings) { warning in
                warningRow(warning)
            }

            if expanded {
                Text("Clear hides current warning IDs until the underlying metric recovers or crosses a different threshold.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(bannerBackground)
        .cornerRadius(6)
    }

    private func warningRow(_ warning: Warning) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(iconColor(warning.severity).opacity(0.8))
                .frame(width: 5, height: 5)
                .padding(.top, 2)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(warning.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                if expanded, let detail = warning.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    private var summaryText: String {
        let criticals = warnings.filter { $0.severity == .critical }.count
        let cautions = warnings.filter { $0.severity == .caution }.count
        if criticals > 0, cautions > 0 {
            return "\(criticals) critical, \(cautions) caution"
        }
        if criticals > 0 {
            return criticals == 1 ? "1 critical warning" : "\(criticals) critical warnings"
        }
        if cautions > 0 {
            return cautions == 1 ? "1 caution" : "\(cautions) cautions"
        }
        return warnings.count == 1 ? "1 notice" : "\(warnings.count) notices"
    }

    private var disclosureTitle: String {
        if expanded { return "Less" }
        if warnings.count > 3 { return "+\(warnings.count - 3)" }
        return "Details"
    }

    private var bannerBackground: Color {
        switch worstSeverity {
        case .critical: return Color.red.opacity(0.08)
        case .caution:  return Color.orange.opacity(0.08)
        case .info:     return Color.blue.opacity(0.08)
        }
    }

    private var worstSeverity: WarningSeverity {
        warnings.map(\.severity).max() ?? .info
    }

    private func iconName(_ severity: WarningSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .caution:  return "exclamationmark.triangle"
        case .info:     return "info.circle"
        }
    }

    private func iconColor(_ severity: WarningSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .caution:  return .orange
        case .info:     return .blue
        }
    }
}

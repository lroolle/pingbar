import SwiftUI

struct WarningBanner: View {
    let warnings: [Warning]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(warnings) { warning in
                HStack(spacing: 6) {
                    Image(systemName: iconName(warning.severity))
                        .foregroundColor(iconColor(warning.severity))
                        .font(.system(size: 10))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(warning.title)
                            .font(.system(size: 11, weight: .medium))
                        if let detail = warning.detail {
                            Text(detail)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(8)
        .background(bannerBackground)
        .cornerRadius(6)
    }

    private var bannerBackground: Color {
        let worst = warnings.map(\.severity).max() ?? .info
        switch worst {
        case .critical: return Color.red.opacity(0.08)
        case .caution:  return Color.orange.opacity(0.08)
        case .info:     return Color.blue.opacity(0.08)
        }
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

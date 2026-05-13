import Foundation

enum WarningSeverity: Int, Comparable {
    case info = 0
    case caution = 1
    case critical = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Warning: Identifiable {
    let id: String
    let severity: WarningSeverity
    let title: String
    let detail: String?
    let timestamp: Date

    init(id: String, severity: WarningSeverity, title: String, detail: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.timestamp = Date()
    }
}

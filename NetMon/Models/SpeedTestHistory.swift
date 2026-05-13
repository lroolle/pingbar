import Foundation

struct SpeedTestHistoryEntry: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let preset: String
    let noProxy: Bool
    let server: String
    let location: String
    let latencyMs: Double
    let downloadBps: UInt64
    let uploadBps: UInt64
}

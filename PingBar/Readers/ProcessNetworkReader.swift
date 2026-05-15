import AppKit
import Foundation

final class ProcessNetworkReader {
    private struct NetTopRow {
        let pid: Int
        let name: String
        let downloaded: Int64
        let uploaded: Int64
    }

    private var previousRows: [Int: NetTopRow] = [:]
    private var previousReadDate: Date?

    func read(limit: Int) -> [NetworkProcessSample] {
        let now = Date()
        let rows = nettopRows()
        defer {
            previousRows = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
            previousReadDate = now
        }

        guard let previousReadDate, !previousRows.isEmpty else { return [] }
        let elapsed = max(now.timeIntervalSince(previousReadDate), 0.5)

        let samples = rows.compactMap { row -> NetworkProcessSample? in
            guard let previous = previousRows[row.pid] else { return nil }
            let downloadDelta = max(0, row.downloaded - previous.downloaded)
            let uploadDelta = max(0, row.uploaded - previous.uploaded)
            let downloadRate = Int64(Double(downloadDelta) / elapsed)
            let uploadRate = Int64(Double(uploadDelta) / elapsed)
            guard downloadRate > 0 || uploadRate > 0 else { return nil }

            return NetworkProcessSample(
                pid: row.pid,
                name: row.name,
                downloadBytesPerSec: downloadRate,
                uploadBytesPerSec: uploadRate
            )
        }

        return samples
            .sorted {
                if $0.totalBytesPerSec == $1.totalBytesPerSec {
                    return max($0.downloadBytesPerSec, $0.uploadBytesPerSec) > max($1.downloadBytesPerSec, $1.uploadBytesPerSec)
                }
                return $0.totalBytesPerSec > $1.totalBytesPerSec
            }
            .prefix(limit)
            .map { $0 }
    }

    private func nettopRows() -> [NetTopRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-L", "1", "-n", "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"]
        task.environment = [
            "NSUnbufferedIO": "YES",
            "LC_ALL": "C",
        ]

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        do {
            try task.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = error.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let outputText = String(data: data, encoding: .utf8)
        else { return [] }

        return outputText
            .split(separator: "\n")
            .dropFirst()
            .compactMap { parseRow(String($0)) }
    }

    private func parseRow(_ line: String) -> NetTopRow? {
        let fields = line.components(separatedBy: ",")
        guard fields.count >= 3,
              let downloaded = Int64(fields[1]),
              let uploaded = Int64(fields[2]),
              let identity = parseIdentity(fields[0])
        else { return nil }

        return NetTopRow(
            pid: identity.pid,
            name: displayName(pid: identity.pid, fallback: identity.name),
            downloaded: downloaded,
            uploaded: uploaded
        )
    }

    private func parseIdentity(_ value: String) -> (name: String, pid: Int)? {
        guard let dot = value.range(of: ".", options: .backwards) else { return nil }
        let name = String(value[..<dot.lowerBound])
        let pidText = value[dot.upperBound...]
        guard let pid = Int(pidText), pid >= 0 else { return nil }
        return (name.isEmpty ? "\(pid)" : name, pid)
    }

    private func displayName(pid: Int, fallback: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let name = app.localizedName,
           !name.isEmpty {
            return name
        }
        return fallback
    }
}

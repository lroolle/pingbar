import Foundation

final class PingReader {
    func ping(host: String, timeout: TimeInterval = 2) -> Double? {
        guard let host = normalizedHost(host) else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: host.contains(":") ? "/sbin/ping6" : "/sbin/ping")
        task.arguments = ["-n", "-c", "1", "-W", "\(Int(timeout * 1000))", host]
        task.environment = ["LC_ALL": "C"]

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        do {
            try task.run()
        } catch {
            return nil
        }

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        _ = error.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { return nil }
        return parseLatency(from: outputText)
    }

    private func normalizedHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://"),
           let components = URLComponents(string: trimmed),
           let host = components.host,
           !host.isEmpty {
            return host
        }

        if trimmed.contains("/") { return nil }
        return trimmed
    }

    private func parseLatency(from output: String) -> Double? {
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: "time=") else { continue }
            let tail = line[range.upperBound...]
            let value = tail.prefix { $0.isNumber || $0 == "." }
            return Double(value)
        }
        return nil
    }
}

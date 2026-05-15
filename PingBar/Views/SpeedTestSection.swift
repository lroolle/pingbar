import SwiftUI

struct SpeedTestSection: View {
    @EnvironmentObject var state: NetworkState
    @State private var preset: SpeedTestPreset = .quick
    @State private var noProxy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Speed Test", systemImage: "speedometer")

            if state.isSpeedTestRunning {
                runningView
            } else {
                controlsView
            }

            if let error = state.speedTestError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            if let result = state.speedTestResult, !state.isSpeedTestRunning {
                resultView(result)
            }
        }
    }

    private var controlsView: some View {
        HStack(spacing: 8) {
            Picker("", selection: $preset) {
                ForEach(SpeedTestPreset.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            .controlSize(.small)

            Toggle("No Proxy", isOn: $noProxy)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .controlSize(.small)

            Spacer()

            Button(action: { state.runSpeedTest(preset: preset, noProxy: noProxy) }) {
                Label("Run", systemImage: "play.fill")
                    .font(.system(size: 10, weight: .medium))
            }
            .controlSize(.small)
        }
    }

    private var runningView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Testing...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Stop") { state.cancelSpeedTest() }
                .controlSize(.small)
                .font(.system(size: 10))
        }
    }

    private func resultView(_ result: NativeSpeedResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if result.status == "partial" {
                    Text("Partial")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.10))
                        .cornerRadius(3)
                }

                if !result.server.isEmpty {
                    Text(result.server)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }
                if !result.location.isEmpty {
                    Text(result.location)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                GridRow {
                    Text("Ping").modifier(InfoLabel())
                    HStack(spacing: 4) {
                        Text(Fmt.latency(result.latencyMs)).modifier(InfoValue())
                        if result.jitterMs > 0 {
                            Text("±\(String(format: "%.0f", result.jitterMs))ms")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if result.downloadBps > 0 {
                    GridRow {
                        Text("Down").modifier(InfoLabel())
                        Text(Fmt.bitsPerSec(result.downloadBps))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                if result.uploadBps > 0 {
                    GridRow {
                        Text("Up").modifier(InfoLabel())
                        Text(Fmt.bitsPerSec(result.uploadBps))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
            }

            if let error = result.error {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}

import SwiftUI

struct SystemView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var stats: SystemStats?

    var body: some View {
        NavigationStack {
            List {
                if let s = stats {
                    Section("Live") {
                        meter("CPU", value: s.cpuPercent ?? 0, label: pct(s.cpuPercent))
                        meter("Memory", value: s.memPercent ?? 0,
                              label: "\(bytes(s.memUsedBytes)) / \(bytes(s.totalRamBytes))")
                        LabeledContent("Load (1m)", value: s.load1.map { String(format: "%.2f", $0) } ?? "—")
                        LabeledContent("Thermal") {
                            if s.thermal.throttling {
                                Label("Throttling \(s.thermal.cpuSpeedLimit ?? 0)%", systemImage: "flame.fill")
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Nominal", systemImage: "checkmark.circle").foregroundStyle(.green)
                            }
                        }
                    }
                    Section("Machine") {
                        LabeledContent("Chip", value: s.chip)
                        LabeledContent("Cores") {
                            Text(coreText(s))
                        }
                        LabeledContent("Memory", value: bytes(s.totalRamBytes))
                        LabeledContent("Model", value: s.model)
                        if let m = s.macos { LabeledContent("macOS", value: m) }
                        LabeledContent("Host", value: s.hostname)
                        LabeledContent("Uptime", value: uptime(s.uptimeSeconds))
                    }
                } else {
                    Section { HStack { ProgressView(); Text("Reading system…").foregroundStyle(.secondary) } }
                }
            }
            .navigationTitle("System")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await pollLoop() }
        }
    }

    private func meter(_ title: String, value: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(label).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(value, 0), 100), total: 100)
                .tint(value > 85 ? .orange : Theme.accent)
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            stats = try? await app.client.system()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func coreText(_ s: SystemStats) -> String {
        if let p = s.performanceCores, let e = s.efficiencyCores {
            return "\(s.cores) (\(p)P + \(e)E)"
        }
        return "\(s.cores)"
    }
    private func pct(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0) } ?? "—" }
    private func bytes(_ b: Int?) -> String {
        guard let b else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }
    private func uptime(_ s: Int) -> String {
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

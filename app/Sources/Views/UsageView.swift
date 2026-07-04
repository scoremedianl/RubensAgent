import SwiftUI

struct UsageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var usage: Usage?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if let rl = usage?.lastRateLimit?.rate_limit_info {
                    Section("Rate limit") {
                        LabeledContent("Status") {
                            Text(rl.status ?? "—")
                                .foregroundStyle(rl.status == "allowed" ? .green : .orange)
                        }
                        if let type = rl.rateLimitType { LabeledContent("Window", value: type) }
                        if let reset = rl.resetsAt {
                            LabeledContent("Resets", value: Self.relative(reset))
                        }
                        if let over = rl.isUsingOverage {
                            LabeledContent("Using overage", value: over ? "yes" : "no")
                        }
                    }
                } else {
                    Section("Rate limit") {
                        Text("No data yet — run a session first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("This daemon (since start)") {
                    LabeledContent("Turns", value: "\(usage?.turns ?? 0)")
                    LabeledContent("Cost", value: String(format: "$%.4f", usage?.totalCostUsd ?? 0))
                    LabeledContent("Input tokens", value: "\(usage?.inputTokens ?? 0)")
                    LabeledContent("Output tokens", value: "\(usage?.outputTokens ?? 0)")
                    LabeledContent("Cache reads", value: "\(usage?.cacheReadTokens ?? 0)")
                }
            }
            .overlay { if loading { ProgressView() } }
            .navigationTitle("Usage & limits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        usage = try? await app.client.usage()
    }

    static func relative(_ unix: Double) -> String {
        let date = Date(timeIntervalSince1970: unix)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

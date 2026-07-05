import SwiftUI

struct UsageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var usage: ClaudeUsage?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading && usage == nil {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading) {
                                Text("Reading Claude usage…")
                                Text("Runs /usage on the Mac — a few seconds.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let u = usage {
                    Section("Limits") {
                        if u.limits.isEmpty {
                            Text("No usage data returned.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(u.limits) { limit in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(limit.label)
                                    Spacer()
                                    Text("\(limit.percent)%").font(.callout.monospaced().weight(.semibold))
                                }
                                ProgressView(value: Double(limit.percent), total: 100)
                                    .tint(limit.percent > 85 ? .red : (limit.percent > 70 ? .orange : Theme.accent))
                                if let r = limit.resets {
                                    Text("resets \(r)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if !contributing(u.raw).isEmpty {
                        Section("What's driving your usage") {
                            Text(contributing(u.raw))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Usage & limits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: {
                        if loading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }.disabled(loading)
                }
            }
            .task { await load() }
        }
    }

    // Strip the limit lines; keep the "What's contributing…" body.
    private func contributing(_ raw: String) -> String {
        guard let r = raw.range(of: "What's contributing", options: .caseInsensitive) else { return "" }
        return String(raw[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        usage = try? await app.client.claudeUsage()
    }
}

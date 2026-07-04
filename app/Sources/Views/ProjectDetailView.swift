import SwiftUI

// Landing page for a chosen project: start a new session or resume history.
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    let project: Project

    @State private var autoApprove = true
    @State private var history: [PersistedSession] = []
    @State private var loading = false

    var body: some View {
        List {
            Section("Project") {
                LabeledContent("Path", value: project.path)
                if let c = project.lastCommit { LabeledContent("Last commit", value: c) }
                if let r = project.remote { LabeledContent("Remote", value: r) }
            }

            Section("New session") {
                Toggle("Full auto (run tools without asking)", isOn: $autoApprove)
                NavigationLink {
                    SessionView(project: project, resumeId: nil, autoApprove: autoApprove)
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                }
            }

            Section("History") {
                if loading { ProgressView() }
                if history.isEmpty && !loading {
                    Text("No past sessions").foregroundStyle(.secondary).font(.caption)
                }
                ForEach(history) { s in
                    NavigationLink {
                        SessionView(project: project, resumeId: s.id, autoApprove: autoApprove)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.id.prefix(8) + "…").font(.body.monospaced())
                            Text(s.modified).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .task(id: project.id) { await loadHistory() }
    }

    private func loadHistory() async {
        loading = true
        defer { loading = false }
        history = (try? await app.client.persistedSessions(cwd: project.path)) ?? []
    }
}

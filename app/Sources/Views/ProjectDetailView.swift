import SwiftUI

// Landing page for a chosen project: start a new session (with model +
// permission mode) or open past sessions read-only.
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    let project: Project

    @AppStorage("session.permissionMode") private var permissionModeRaw = PermissionMode.bypass.rawValue
    @AppStorage("session.model") private var model = ""
    @State private var history: [PersistedSession] = []
    @State private var loading = false

    private var permissionMode: PermissionMode {
        PermissionMode(rawValue: permissionModeRaw) ?? .bypass
    }

    var body: some View {
        List {
            Section("Project") {
                LabeledContent("Path", value: project.path)
                if let c = project.lastCommit { LabeledContent("Last commit", value: c) }
            }

            Section("New session") {
                Picker("Model", selection: $model) {
                    ForEach(modelOptions) { m in Text(m.label).tag(m.id) }
                }
                Picker("Permissions", selection: $permissionModeRaw) {
                    ForEach(PermissionMode.allCases) { m in Text(m.label).tag(m.rawValue) }
                }
                Text(permissionMode.detail).font(.caption).foregroundStyle(.secondary)
                NavigationLink {
                    SessionView(project: project, resumeId: nil,
                                permissionMode: permissionMode, model: model)
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
                        TranscriptView(project: project, sessionId: s.id,
                                       permissionMode: permissionMode, model: model)
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

import SwiftUI

// Landing page for a chosen project: git actions, start a new session (with
// model + permission mode), or open past sessions read-only.
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    let project: Project

    @AppStorage("session.model") private var model = ""
    @State private var history: [PersistedSession] = []
    @State private var loading = false

    // Git
    @State private var branchInfo: BranchInfo?
    @State private var gitBusy = false
    @State private var gitMessage: String?

    // Claude Code always runs full-auto.
    private let permissionMode: PermissionMode = .bypass

    var body: some View {
        List {
            Section("New session") {
                Picker("Model", selection: $model) {
                    ForEach(modelOptions) { m in Text(m.label).tag(m.id) }
                }
                .pickerStyle(.menu)
                Label("Full auto — Claude runs tools without asking", systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    manager.open(project: project, permissionMode: permissionMode, model: model)
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                }
            }

            gitSection

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

            Section("Details") {
                if let c = project.lastCommit { LabeledContent("Last commit", value: c) }
                LabeledContent("Path", value: project.path).font(.caption)
            }
        }
        .navigationTitle(project.name)
        .task(id: project.id) { await loadHistory(); await loadBranches() }
    }

    // Base branches present in this repo, for one-tap switching.
    private var baseBranches: [String] {
        ["main", "develop", "master"].filter { branchInfo?.branches.contains($0) == true }
    }

    private var gitSection: some View {
        Section("Git") {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                Menu(branchInfo?.current ?? project.branch ?? "branch") {
                    ForEach(branchInfo?.branches ?? [], id: \.self) { b in
                        Button(b) { Task { await switchBranch(b) } }
                    }
                }
                Spacer()
                Button {
                    Task { await pull() }
                } label: {
                    if gitBusy { ProgressView().controlSize(.small) }
                    else { Label("Pull", systemImage: "arrow.down.circle") }
                }
                .buttonStyle(.borderless)
                .disabled(gitBusy)
            }
            if !baseBranches.isEmpty {
                HStack {
                    Text("Switch to").font(.caption).foregroundStyle(.secondary)
                    ForEach(baseBranches, id: \.self) { b in
                        Button(b) { Task { await switchBranch(b) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(gitBusy || branchInfo?.current == b)
                    }
                }
            }
            if let m = gitMessage {
                Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }

    private func loadHistory() async {
        loading = true; defer { loading = false }
        history = (try? await app.client.persistedSessions(cwd: project.path)) ?? []
    }
    private func loadBranches() async {
        branchInfo = try? await app.client.branches(cwd: project.path)
    }
    private func pull() async {
        gitBusy = true; defer { gitBusy = false }
        do { try await app.client.gitPull(cwd: project.path); gitMessage = "Pulled." }
        catch { gitMessage = error.localizedDescription }
    }
    private func switchBranch(_ b: String) async {
        gitBusy = true; defer { gitBusy = false }
        do {
            try await app.client.gitCheckout(cwd: project.path, branch: b)
            gitMessage = "Switched to \(b)."
            await loadBranches()
        } catch { gitMessage = error.localizedDescription }
    }
}

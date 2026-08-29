import SwiftUI

// Landing page for a chosen project: pick which coding agent to run, git
// actions, start a new session, or open past sessions read-only.
struct ProjectDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    let project: Project

    @AppStorage("session.agent") private var agentRaw = AgentKind.claude.rawValue
    @AppStorage("session.model") private var model = ""
    @State private var history: [PersistedSession] = []
    @State private var loading = false
    @State private var startingSession = false

    // Git
    @State private var branchInfo: BranchInfo?
    @State private var gitBusy = false
    @State private var gitMessage: String?

    // Agents always run full-auto.
    private let permissionMode: PermissionMode = .bypass

    private var agent: AgentKind { AgentKind(rawValue: agentRaw) ?? .claude }
    private var status: AgentInfo? { app.agent(agent) }
    private var canStart: Bool { status?.usable ?? false }

    // Claude's presets, or whatever OpenCode reported it can run.
    private var models: [ModelOption] {
        let reported = (status?.models ?? []).map { ModelOption(id: $0, label: $0) }
        return reported.isEmpty ? agent.staticModels : ([ModelOption(id: "", label: "Default")] + reported)
    }

    var body: some View {
        List {
            newSessionSection

            Section("Files") {
                NavigationLink {
                    FileBrowserView(dirPath: project.path, title: project.name)
                } label: {
                    Label("Browse files", systemImage: "folder")
                }
            }

            if project.git { gitSection }

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
        .task { if app.agents.isEmpty { await app.loadAgents() } }
    }

    // MARK: New session

    private var newSessionSection: some View {
        Section("New session") {
            Picker("Agent", selection: $agentRaw) {
                ForEach(AgentKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.symbol).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: agentRaw) { _, _ in
                // Model ids don't carry across agents (claude-opus-5 means
                // nothing to Codex), so reset to that agent's default.
                model = ""
            }

            Picker("Model", selection: $model) {
                ForEach(models) { m in Text(m.label).tag(m.id) }
            }
            .pickerStyle(.menu)
            .disabled(models.count <= 1)

            if let status, !status.usable {
                agentUnavailable(status)
            } else {
                Label("Full auto — \(agent.label) runs tools without asking", systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                startingSession = true
                Task {
                    await manager.openTerminal(project: project, model: model, agent: agent)
                    startingSession = false
                }
            } label: {
                HStack(spacing: 8) {
                    if startingSession { ProgressView().controlSize(.small) }
                    Label(startingSession ? "Starting…" : "Start session", systemImage: "play.circle.fill")
                }
            }
            .disabled(startingSession || !canStart)

            Button {
                startingSession = true
                Task {
                    await manager.openTerminal(project: project, model: model, agent: agent, resume: true)
                    startingSession = false
                }
            } label: {
                Label("Resume last session", systemImage: "arrow.uturn.left.circle")
            }
            .disabled(startingSession || !canStart)
        }
    }

    @ViewBuilder private func agentUnavailable(_ status: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.installed ? "\(agent.label) is not signed in" : "\(agent.label) is not installed",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            Text(status.installed ? agent.loginHint : "Install it on the Mac first.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check again") { Task { await app.loadAgents(force: true) } }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    // MARK: Git

    private var gitSection: some View {
        Section("Git") {
            if let info = branchInfo {
                NavigationLink {
                    BranchPickerView(project: project, info: info) { branch in
                        gitMessage = "Switched to \(branch)."
                        Task { await loadBranches() }
                    }
                    .environmentObject(app)
                } label: {
                    HStack {
                        Label("Branch", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text(info.current).font(.body.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(info.branches.count)")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            } else {
                HStack {
                    Label("Branch", systemImage: "arrow.triangle.branch")
                    Spacer()
                    Text(project.branch ?? "…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await pull() }
            } label: {
                if gitBusy { ProgressView().controlSize(.small) }
                else { Label("Pull", systemImage: "arrow.down.circle") }
            }
            .disabled(gitBusy)
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
}

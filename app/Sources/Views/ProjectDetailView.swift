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
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RelativeTime.friendly(s.modified)).font(.body)
                                Text(s.id.prefix(8) + "…")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let age = RelativeTime.short(s.modified) {
                                Text(age).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Details") {
                if let c = project.lastCommit {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last commit").font(.caption).foregroundStyle(.secondary)
                        Text(c).font(.callout).lineLimit(3)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Path").font(.caption).foregroundStyle(.secondary)
                    Text(project.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(project.name)
        .task(id: project.id) { await loadHistory(); await loadBranches() }
        .task { if app.agents.isEmpty { await app.loadAgents() } }
    }

    // MARK: New session

    private var newSessionSection: some View {
        Section("New session") {
            // Cards rather than a menu: you see all three agents and whether
            // each is actually ready without opening anything.
            HStack(spacing: 10) {
                ForEach(AgentKind.allCases) { kind in
                    AgentCard(kind: kind, status: app.agent(kind), selected: kind == agent) {
                        agentRaw = kind.rawValue
                        // Model ids don't carry across agents (claude-opus-5
                        // means nothing to Codex), so reset to the default.
                        model = ""
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.vertical, 4)

            // A menu is fine for Claude's six presets, but OpenCode with
            // OpenRouter reports hundreds — that needs a searchable list.
            NavigationLink {
                ModelPickerView(agent: agent, options: models, selection: $model)
            } label: {
                HStack {
                    Label("Model", systemImage: "cpu")
                    Spacer()
                    ModelChip(modelId: model)
                    if models.count > 1 {
                        Text("\(models.count)")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .disabled(models.count <= 1)

            if let status, !status.usable {
                agentUnavailable(status)
            } else {
                Label("Full auto — \(agent.label) runs tools without asking", systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    startingSession = true
                    Task {
                        await manager.openTerminal(project: project, model: model, agent: agent)
                        startingSession = false
                    }
                } label: {
                    HStack(spacing: 7) {
                        if startingSession { ProgressView().controlSize(.small) }
                        else { Image(systemName: "play.fill") }
                        Text(startingSession ? "Starting…" : "Start \(agent.label)")
                    }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(canStart ? AnyShapeStyle(agent.gradient)
                                         : AnyShapeStyle(Color.secondary.opacity(0.25)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(startingSession || !canStart)

                Button {
                    startingSession = true
                    Task {
                        await manager.openTerminal(project: project, model: model, agent: agent, resume: true)
                        startingSession = false
                    }
                } label: {
                    Label("Resume", systemImage: "arrow.uturn.left")
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(startingSession || !canStart)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private func agentUnavailable(_ status: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline(status), systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            Text(status.detail ?? (status.installed ? agent.loginHint : "Install it on the Mac first."))
                .font(.caption).foregroundStyle(.secondary)
            Button {
                Task { await app.loadAgents(force: true) }
            } label: {
                Label("Check again", systemImage: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private func headline(_ status: AgentInfo) -> String {
        if !status.installed { return "\(agent.label) is not installed" }
        // Don't accuse the user of not signing in when the probe just failed.
        if !status.authKnown { return "Could not check \(agent.label)'s login" }
        return "\(agent.label) is not signed in"
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

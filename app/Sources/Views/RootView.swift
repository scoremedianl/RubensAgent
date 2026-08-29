import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    @State private var sheet: SheetKind?
    @State private var refreshing = false
    @State private var query = ""

    enum SheetKind: Int, Identifiable { case settings, loops, usage, memory, runs, system, repos; var id: Int { rawValue } }

    // Filtering happens locally on the already-loaded lists, so typing is
    // instant — no round trip to the Mac for every keystroke.
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var filteredProjects: [Project] {
        let q = trimmedQuery
        guard !q.isEmpty else { return app.projects }
        return app.projects.filter {
            $0.name.lowercased().contains(q)
                || $0.path.lowercased().contains(q)
                || ($0.branch?.lowercased().contains(q) ?? false)
        }
    }

    private var filteredTerminals: [TermSession] {
        let q = trimmedQuery
        guard !q.isEmpty else { return manager.terminals }
        return manager.terminals.filter {
            $0.projectName.lowercased().contains(q)
                || $0.cwd.lowercased().contains(q)
                || $0.kind.label.lowercased().contains(q)
        }
    }

    private var noMatches: Bool {
        !trimmedQuery.isEmpty && filteredProjects.isEmpty && filteredTerminals.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $manager.selection) {
                if trimmedQuery.isEmpty {
                    Section {
                        SystemWidget(system: app.system) { sheet = .system }
                            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 2, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                if !filteredTerminals.isEmpty {
                    Section {
                        ForEach(filteredTerminals) { term in
                            TerminalRow(term: term).tag(SidebarItem.session(term.name))
                        }
                    } header: {
                        sectionHeader("Running", filteredTerminals.count,
                                      working: filteredTerminals.filter(\.busy).count)
                    }
                }
                Section {
                    ForEach(filteredProjects) { project in
                        ProjectRow(project: project).tag(SidebarItem.project(project.path))
                    }
                } header: {
                    sectionHeader("Projects", filteredProjects.count, working: 0)
                }
            }
            #if os(macOS)
            .searchable(text: $query, placement: .sidebar, prompt: "Search projects & sessions")
            #else
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search projects & sessions")
            #endif
            .navigationTitle("Claude Console")
            .toolbar {
                ToolbarItemGroup {
                    Button { sheet = .repos } label: { Image(systemName: "plus") }
                    Menu {
                        Button { sheet = .runs } label: { Label("Persistent runs", systemImage: "terminal") }
                        Button { sheet = .system } label: { Label("System", systemImage: "cpu") }
                        Button { sheet = .usage } label: { Label("Usage & limits", systemImage: "gauge.with.dots.needle.67percent") }
                        Button { sheet = .memory } label: { Label("Memory", systemImage: "brain") }
                        Button { sheet = .loops } label: { Label("Loops", systemImage: "clock.arrow.circlepath") }
                        Button { sheet = .settings } label: { Label("Connection", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { Task { await refresh() } } label: {
                        if refreshing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(refreshing)
                }
            }
            .overlay {
                if noMatches {
                    ContentUnavailableView.search(text: query)
                } else if app.projects.isEmpty && trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        app.reachable ? "No projects" : "Not connected",
                        systemImage: app.reachable ? "folder" : "wifi.slash",
                        description: Text(app.statusMessage)
                    )
                }
            }
        } detail: {
            NavigationStack { detailView }
        }
        .task { await refresh() }
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .settings: ConnectionView()
                case .loops: LoopsView()
                case .usage: UsageView()
                case .memory: MemoryView()
                case .runs: RunsView()
                case .system: SystemView()
                case .repos: AddProjectView()
                }
            }
            .environmentObject(app)
            .environmentObject(manager)
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
    }

    private func sectionHeader(_ title: String, _ count: Int, working: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            if working > 0 {
                Text("\(working) working")
                    .foregroundStyle(.green)
            }
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .textCase(nil)
    }

    @ViewBuilder private var detailView: some View {
        switch manager.selection {
        case .session(let name):
            // .id(name) forces a fresh TerminalView (and poll loop) per terminal,
            // so switching between terminals doesn't carry over stale state.
            if let t = manager.term(name) { TerminalView(term: t).id(name) }
            else { placeholder }
        case .project(let path):
            if let p = app.projects.first(where: { $0.path == path }) { ProjectDetailView(project: p) }
            else { placeholder }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(AgentKind.allCases) { kind in
                    AgentGlyph(kind: kind, size: 34, active: app.agent(kind)?.usable ?? false)
                }
            }
            VStack(spacing: 5) {
                Text("Claude Console").font(.title2.weight(.semibold))
                Text(app.reachable
                     ? "Pick a project to start a session, or open a running one."
                     : app.statusMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        await app.checkHealth()
        if app.reachable {
            app.startSystemPolling()
            await app.loadProjects()
            await manager.refreshTerminals()
            // force: logging an agent in on the Mac must show up when you
            // press refresh, not up to five minutes later.
            await app.loadAgents(force: true)
        } else if app.token.isEmpty {
            sheet = .settings
        }
    }
}

// A live terminal in the sidebar: which agent, which project, is it working.
struct TerminalRow: View {
    let term: TermSession

    var body: some View {
        HStack(spacing: 10) {
            AgentAvatar(kind: term.kind, running: term.running)
            VStack(alignment: .leading, spacing: 3) {
                Text(term.projectName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(term.running ? .primary : .secondary)
                    .lineLimit(1)
                subtitle
            }
            Spacer(minLength: 4)
            // A quiet spinner on the trailing edge, rather than something
            // pulsing next to the agent icon.
            if term.busy { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 3)
    }

    // Repeating "Claude Code · Opus 5" on every row says nothing when every
    // session is Claude — the avatar already carries the agent. Show what
    // actually differs per row instead.
    @ViewBuilder private var subtitle: some View {
        if !term.running {
            Text("stopped · tap to resume")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                if let m = term.model, !m.isEmpty {
                    ModelChip(modelId: m, compact: true)
                }
                if term.busy {
                    Text("working…")
                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                } else if let age = RelativeTime.short(term.lastActivity ?? term.startedAt) {
                    Text(age).font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
    }
}

// A running session in the sidebar, live-updating from its socket.
struct SessionRow: View {
    let entry: SessionEntry
    @ObservedObject var socket: SessionSocket

    init(entry: SessionEntry) {
        self.entry = entry
        _socket = ObservedObject(wrappedValue: entry.socket)
    }

    var body: some View {
        HStack(spacing: 8) {
            if socket.working { ProgressView().controlSize(.small) }
            else { Circle().fill(socket.connected ? .green : .secondary).frame(width: 8, height: 8) }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.body)
                Text(socket.items.last?.text ?? "…")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: project.git ? "chevron.left.slash.chevron.right" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.body).lineLimit(1)
                HStack(spacing: 5) {
                    if project.git, let b = project.branch {
                        Label(b, systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    } else if !project.git {
                        Text("Folder")
                    }
                    if let a = project.lastActivity {
                        Text("· \(Self.relative(a))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return "" }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .abbreviated
        return rel.localizedString(for: d, relativeTo: Date())
    }
}

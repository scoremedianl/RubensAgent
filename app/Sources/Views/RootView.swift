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
                    Section("Running") {
                        ForEach(filteredTerminals) { term in
                            TerminalRow(term: term).tag(SidebarItem.session(term.name))
                        }
                    }
                }
                Section("Projects") {
                    ForEach(filteredProjects) { project in
                        ProjectRow(project: project).tag(SidebarItem.project(project.path))
                    }
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
        ContentUnavailableView("Pick a project or session", systemImage: "sidebar.left")
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
        HStack(spacing: 9) {
            ActivityDot(busy: term.busy, running: term.running, tint: term.kind.tint)
            AgentGlyph(kind: term.kind, size: 20, active: term.running)
            VStack(alignment: .leading, spacing: 2) {
                Text(term.projectName)
                    .font(.body)
                    .foregroundStyle(term.running ? .primary : .secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(term.busy ? "working…" : (term.running ? term.kind.label : "stopped · resume"))
                        .font(.caption)
                        .foregroundStyle(term.busy ? term.kind.tint : .secondary)
                    if let m = term.model, !m.isEmpty {
                        ModelChip(modelId: m, compact: true)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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
            Image(systemName: project.git ? "shippingbox.fill" : "folder.fill")
                .font(.caption)
                .foregroundStyle(project.git ? Theme.accent.opacity(0.75) : .secondary)
                .frame(width: 20)
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

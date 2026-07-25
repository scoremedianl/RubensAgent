import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    @State private var sheet: SheetKind?
    @State private var refreshing = false

    enum SheetKind: Int, Identifiable { case settings, loops, usage, memory, runs, system, repos; var id: Int { rawValue } }

    var body: some View {
        NavigationSplitView {
            List(selection: $manager.selection) {
                Section {
                    SystemWidget(system: app.system) { sheet = .system }
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !manager.terminals.isEmpty {
                    Section("Running") {
                        ForEach(manager.terminals) { term in
                            HStack(spacing: 8) {
                                Group {
                                    if term.busy {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Circle().fill(term.running ? .green : .secondary).frame(width: 8, height: 8)
                                    }
                                }
                                .frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(term.projectName).font(.body)
                                    Text(term.busy ? "working…" : "terminal")
                                        .font(.caption)
                                        .foregroundStyle(term.busy ? Theme.accent : .secondary)
                                }
                            }
                            .tag(SidebarItem.session(term.name))
                        }
                    }
                }
                Section("Projects") {
                    ForEach(app.projects) { project in
                        ProjectRow(project: project).tag(SidebarItem.project(project.path))
                    }
                }
            }
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
                if app.projects.isEmpty {
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
        } else if app.token.isEmpty {
            sheet = .settings
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
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name).font(.body)
            HStack(spacing: 6) {
                if project.git, let b = project.branch {
                    Label(b, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon)
                } else if !project.git {
                    Label("Folder", systemImage: "folder")
                }
                if let a = project.lastActivity {
                    Text("· \(Self.relative(a))")
                }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return "" }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .abbreviated
        return rel.localizedString(for: d, relativeTo: Date())
    }
}

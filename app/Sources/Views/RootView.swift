import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    @State private var showSettings = false
    @State private var showLoops = false
    @State private var showUsage = false
    @State private var showMemory = false

    var body: some View {
        NavigationSplitView {
            List(selection: $manager.selection) {
                if !manager.entries.isEmpty {
                    Section("Running") {
                        ForEach(manager.entries) { entry in
                            SessionRow(entry: entry).tag(SidebarItem.session(entry.id))
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
                    Button { showUsage = true } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                    Button { showMemory = true } label: { Image(systemName: "brain") }
                    Button { showLoops = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
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
            detailView
        }
        .task { await refresh() }
        .sheet(isPresented: $showSettings) { ConnectionView() }
        .sheet(isPresented: $showLoops) { LoopsView() }
        .sheet(isPresented: $showUsage) { UsageView() }
        .sheet(isPresented: $showMemory) { MemoryView() }
    }

    @ViewBuilder private var detailView: some View {
        switch manager.selection {
        case .session(let id):
            if let e = manager.entry(id) { SessionView(entry: e) }
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
        await app.checkHealth()
        if app.reachable {
            await app.loadProjects()
            await manager.refreshLive(projects: app.projects)
        } else {
            showSettings = app.token.isEmpty
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
                if let b = project.branch {
                    Label(b, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon)
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

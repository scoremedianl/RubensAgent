import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var selection: Project?
    @State private var showSettings = false
    @State private var showLoops = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Projects") {
                    ForEach(app.projects) { project in
                        NavigationLink(value: project) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name).font(.body)
                                if let b = project.branch {
                                    Text(b).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Claude Console")
            .toolbar {
                ToolbarItemGroup {
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
            if let project = selection {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView("Pick a project", systemImage: "sidebar.left")
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $showSettings) { ConnectionView() }
        .sheet(isPresented: $showLoops) { LoopsView() }
    }

    private func refresh() async {
        await app.checkHealth()
        if app.reachable { await app.loadProjects() }
        else { showSettings = app.token.isEmpty }
    }
}

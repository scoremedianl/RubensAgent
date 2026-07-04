import Foundation

// What the sidebar selection points at.
enum SidebarItem: Hashable {
    case project(String)   // project path
    case session(String)   // entry id
}

// One open chat session in the app. The socket lives here (in the manager),
// NOT in a view, so a session keeps running and streaming while you navigate
// elsewhere or close its screen.
struct SessionEntry: Identifiable {
    let id: String
    let project: Project
    let socket: SessionSocket
    var title: String
}

// App-wide registry of live sessions. Fixes: reattaching after the app closes,
// running several sessions at once, switching projects without killing a
// session, and the sessions overview.
@MainActor
final class SessionManager: ObservableObject {
    @Published var entries: [SessionEntry] = []
    @Published var terminals: [TermSession] = []
    @Published var selection: SidebarItem?

    // MARK: Terminal sessions (tmux-mirrored, the primary session model)

    func refreshTerminals() async {
        terminals = (try? await Bridge.client.terms()) ?? []
        // Don't keep pointing at a terminal that no longer exists.
        if case .session(let name) = selection, term(name) == nil {
            selection = nil
        }
    }

    func openTerminal(project: Project, model: String) async {
        guard let t = try? await Bridge.client.startTerm(cwd: project.path, model: model) else { return }
        await refreshTerminals()
        selection = .session(t.name)
    }

    func term(_ name: String) -> TermSession? { terminals.first { $0.name == name } }

    // Start a brand-new session and select it.
    @discardableResult
    func open(project: Project, resumeId: String? = nil,
              permissionMode: PermissionMode, model: String) -> SessionEntry {
        let socket = Bridge.makeSocket()
        let id = UUID().uuidString
        socket.start(cwd: project.path, resumeId: resumeId,
                     permissionMode: permissionMode.rawValue, model: model)
        let entry = SessionEntry(id: id, project: project, socket: socket, title: project.name)
        entries.append(entry)
        selection = .session(id)
        return entry
    }

    // Re-join a session that is still running on the daemon (e.g. after the
    // app was closed while it worked).
    func reattach(project: Project, sessionId: String) {
        guard !entries.contains(where: { $0.socket.sessionId == sessionId || $0.id == sessionId }) else { return }
        let socket = Bridge.makeSocket()
        socket.attach(cwd: project.path, sessionId: sessionId)
        entries.append(SessionEntry(id: sessionId, project: project, socket: socket, title: project.name))
    }

    func entry(_ id: String) -> SessionEntry? { entries.first { $0.id == id } }

    func close(_ id: String) {
        entry(id)?.socket.stop()
        entries.removeAll { $0.id == id }
        if selection == .session(id) { selection = nil }
    }

    // On launch / refresh, reattach to sessions still alive on the daemon so
    // they show up and can be steered again.
    func refreshLive(projects: [Project]) async {
        guard let live = try? await Bridge.client.liveSessions() else { return }
        for s in live where s.alive {
            if entries.contains(where: { $0.socket.sessionId == s.id }) { continue }
            let project = projects.first { $0.path == s.cwd }
                ?? Project(name: s.project ?? (s.cwd as NSString).lastPathComponent, path: s.cwd)
            reattach(project: project, sessionId: s.id)
        }
    }
}

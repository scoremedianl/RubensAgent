import Foundation
import SwiftUI

// Connection configuration + shared app state. Persisted in UserDefaults.
@MainActor
final class AppState: ObservableObject {
    /// Every Mac you've set up, and which one the app is talking to.
    @Published var servers: [MacServer] = ServerStore.load()
    @Published var selectedServerID: String? = ServerStore.selectedID

    @Published var health: Health?
    @Published var reachable = false
    @Published var statusMessage = "Not connected"
    @Published var projects: [Project] = []
    @Published var system: SystemStats?
    @Published var agents: [AgentInfo] = []

    private var systemTask: Task<Void, Never>?

    /// The Mac currently being driven. Everything else reads through this.
    var server: MacServer? {
        if let id = selectedServerID, let match = servers.first(where: { $0.id == id }) { return match }
        return servers.first
    }
    var host: String { server?.host ?? "" }
    var port: Int { server?.port ?? 8787 }
    var token: String { server?.token ?? "" }

    var client: BridgeClient { BridgeClient(host: host, port: port, token: token) }

    // Poll live system stats for the status widget.
    func startSystemPolling() {
        guard systemTask == nil else { return }
        systemTask = Task { [weak self] in
            while !Task.isCancelled {
                if let s = try? await self?.client.system() { self?.system = s }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    var isConfigured: Bool { server?.isConfigured ?? false }

    // MARK: Managing Macs

    func addServer(_ s: MacServer) {
        servers.append(s)
        persist()
        if servers.count == 1 { select(s.id) }
    }

    func updateServer(_ s: MacServer) {
        guard let i = servers.firstIndex(where: { $0.id == s.id }) else { return }
        servers[i] = s
        persist()
    }

    func removeServer(_ id: String) {
        servers.removeAll { $0.id == id }
        persist()
        // Don't leave the app pointed at a Mac that no longer exists.
        if selectedServerID == id { selectedServerID = servers.first?.id }
        if let id = selectedServerID { ServerStore.select(id) }
    }

    private func persist() { ServerStore.save(servers) }

    /// Point the app at another Mac. Everything on screen belongs to the old
    /// one — sessions, projects, stats — so it all has to go.
    func select(_ id: String) {
        guard selectedServerID != id else { return }
        selectedServerID = id
        ServerStore.select(id)
        systemTask?.cancel(); systemTask = nil
        health = nil
        system = nil
        projects = []
        agents = []
        reachable = false
        statusMessage = "Switching…"
    }

    func checkHealth() async {
        do {
            let h = try await client.health()
            health = h; reachable = true
            statusMessage = "Connected · bridge \(h.version)"
        } catch {
            reachable = false
            statusMessage = "Unreachable: \(error.localizedDescription)"
        }
    }

    // Which coding agents can be started. Cheap and cached on the daemon.
    func loadAgents(force: Bool = false) async {
        guard let res = try? await client.agents(force: force) else { return }
        agents = res.agents
        // The very first call kicks off the probe and answers "checking…";
        // come back once so the picker doesn't sit there greyed out.
        if res.pending == true && !force {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if let again = try? await client.agents() { agents = again.agents }
        }
    }

    func agent(_ kind: AgentKind) -> AgentInfo? { agents.first { $0.id == kind.rawValue } }

    func loadProjects() async {
        do { projects = try await client.projects() }
        catch { statusMessage = "Projects failed: \(error.localizedDescription)" }
    }

    func newSocket() -> SessionSocket {
        SessionSocket(host: host, port: port, token: token)
    }
}

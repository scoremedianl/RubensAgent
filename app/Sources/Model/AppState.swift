import Foundation
import SwiftUI

// Connection configuration + shared app state. Persisted in UserDefaults.
@MainActor
final class AppState: ObservableObject {
    @AppStorage("bridge.host") var host: String = "100.121.84.34"
    @AppStorage("bridge.port") var port: Int = 8787
    @AppStorage("bridge.token") var token: String = ""

    @Published var health: Health?
    @Published var reachable = false
    @Published var statusMessage = "Not connected"
    @Published var projects: [Project] = []
    @Published var system: SystemStats?
    @Published var agents: [AgentInfo] = []

    private var systemTask: Task<Void, Never>?

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
    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }

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
        if res.pending == true {
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

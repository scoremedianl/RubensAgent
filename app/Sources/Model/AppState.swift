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

    func loadProjects() async {
        do { projects = try await client.projects() }
        catch { statusMessage = "Projects failed: \(error.localizedDescription)" }
    }

    func newSocket() -> SessionSocket {
        SessionSocket(host: host, port: port, token: token)
    }
}

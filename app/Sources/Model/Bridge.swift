import Foundation

// Single source of truth for the bridge connection, read from the same
// UserDefaults keys AppState/@AppStorage use. Lets non-View types (managers,
// sockets) build clients/sockets without threading config everywhere.
enum Bridge {
    static var host: String { UserDefaults.standard.string(forKey: "bridge.host") ?? "" }
    static var port: Int {
        let p = UserDefaults.standard.integer(forKey: "bridge.port")
        return p == 0 ? 8787 : p
    }
    static var token: String { UserDefaults.standard.string(forKey: "bridge.token") ?? "" }

    static var client: BridgeClient { BridgeClient(host: host, port: port, token: token) }
    @MainActor static func makeSocket() -> SessionSocket { SessionSocket(host: host, port: port, token: token) }
}

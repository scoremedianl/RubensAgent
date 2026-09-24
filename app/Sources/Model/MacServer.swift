import Foundation

// One Mac running the bridge daemon.
//
// The app talks to a single Mac at a time; this is the list you pick from.
// Each Mac has its own token (the daemon generates one per machine), so a
// server is host + port + token together — swapping only the host would
// authenticate against the wrong machine.
struct MacServer: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var host: String
    var port: Int = 8787
    var token: String

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }
    /// What to show when the name is blank.
    var displayName: String { name.isEmpty ? host : name }
}

// Persistence for the server list and which one is selected.
//
// Kept as plain UserDefaults access rather than @AppStorage so non-View types
// (Bridge, SessionManager) can read the selection without a SwiftUI context.
enum ServerStore {
    private static let listKey = "bridge.servers"
    private static let selectedKey = "bridge.selectedServer"
    private static let defaultKey = "bridge.defaultServer"

    // Pre-multi-Mac keys, still read once to carry the existing setup over.
    private static let legacyHost = "bridge.host"
    private static let legacyPort = "bridge.port"
    private static let legacyToken = "bridge.token"

    static func load() -> [MacServer] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: listKey),
           let list = try? JSONDecoder().decode([MacServer].self, from: data),
           !list.isEmpty {
            return list
        }
        // First run after the update: turn the single configured Mac into the
        // first entry so nobody has to re-enter a token they already have.
        let host = defaults.string(forKey: legacyHost) ?? ""
        let token = defaults.string(forKey: legacyToken) ?? ""
        guard !host.isEmpty || !token.isEmpty else { return [] }
        let port = defaults.integer(forKey: legacyPort)
        let migrated = MacServer(name: "Mac mini", host: host,
                                 port: port == 0 ? 8787 : port, token: token)
        save([migrated])
        select(migrated.id)
        return [migrated]
    }

    static func save(_ servers: [MacServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: listKey)
    }

    static var selectedID: String? {
        UserDefaults.standard.string(forKey: selectedKey)
    }

    static func select(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedKey)
    }

    /// The Mac to open on, if one is pinned. Without it the app resumes
    /// whichever Mac you used last.
    static var defaultID: String? {
        get { UserDefaults.standard.string(forKey: defaultKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: defaultKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultKey) }
        }
    }

    /// Which Mac to use at launch. Resolved once and written back, so `Bridge`
    /// — which reads the selection, not the default — agrees from the start.
    static func resolveStartupSelection() -> String? {
        let servers = load()
        guard let first = servers.first else { return nil }
        if let pinned = defaultID, servers.contains(where: { $0.id == pinned }) {
            select(pinned)
            return pinned
        }
        if let last = selectedID, servers.contains(where: { $0.id == last }) { return last }
        select(first.id)
        return first.id
    }

    /// The active Mac: the selected one, or the first if the selection is gone.
    static func selected() -> MacServer? {
        let servers = load()
        if let id = selectedID, let match = servers.first(where: { $0.id == id }) { return match }
        return servers.first
    }
}

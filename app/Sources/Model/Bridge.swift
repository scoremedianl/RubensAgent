import Foundation

// Single source of truth for the bridge connection: whichever Mac is currently
// selected in ServerStore. Lets non-View types (managers, sockets) build
// clients without threading config everywhere, and means switching Macs takes
// effect everywhere at once — nothing caches a host of its own.
enum Bridge {
    static var server: MacServer? { ServerStore.selected() }

    static var host: String { server?.host ?? "" }
    static var port: Int { server?.port ?? 8787 }
    static var token: String { server?.token ?? "" }

    static var client: BridgeClient { BridgeClient(host: host, port: port, token: token) }
    @MainActor static func makeSocket() -> SessionSocket { SessionSocket(host: host, port: port, token: token) }
}

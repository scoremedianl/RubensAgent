import SwiftUI

@main
struct ClaudeConsoleApp: App {
    @StateObject private var app = AppState()
    @StateObject private var manager = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(manager)
                .task { await app.checkHealth() }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

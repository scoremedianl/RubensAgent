import SwiftUI

@main
struct ClaudeConsoleApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task { await app.checkHealth() }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        #endif
    }
}

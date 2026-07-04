import SwiftUI

// Read-only view of a past session's transcript, with the option to resume it
// as a live session.
struct TranscriptView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    let project: Project
    let sessionId: String
    let permissionMode: PermissionMode
    let model: String

    @State private var items: [ChatItem] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(items) { ChatBubble(item: $0) }
            }
            .padding()
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.open(project: project, resumeId: sessionId,
                                 permissionMode: permissionMode, model: model)
                } label: { Label("Continue", systemImage: "play.fill") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let events = (try? await app.client.transcript(cwd: project.path, id: sessionId)) ?? []
        items = ChatItem.list(from: events)
    }
}

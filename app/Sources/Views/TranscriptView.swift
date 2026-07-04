import SwiftUI

// Read-only view of a past session's transcript, with the option to resume it
// as a live session.
struct TranscriptView: View {
    @EnvironmentObject var app: AppState
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
                NavigationLink {
                    SessionView(project: project, resumeId: sessionId,
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
        items = TranscriptView.itemize(events)
    }

    // Convert raw transcript events into chat bubbles.
    static func itemize(_ events: [StreamEvent]) -> [ChatItem] {
        var out: [ChatItem] = []
        for e in events {
            guard let content = e.message?.content else { continue }
            let role = e.message?.role ?? e.type
            for block in content {
                switch block.type {
                case "text":
                    if let t = block.text, !t.isEmpty {
                        out.append(ChatItem(kind: role == "user" ? .user : .assistant, text: t))
                    }
                case "tool_use":
                    out.append(ChatItem(kind: .tool, text: "🔧 \(block.name ?? "tool")"))
                case "tool_result":
                    out.append(ChatItem(kind: .toolResult, text: "✓ result"))
                default: break
                }
            }
        }
        return out
    }
}

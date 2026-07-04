import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject var app: AppState
    let run: Run
    let onChange: () async -> Void

    @State private var items: [ChatItem] = []
    @State private var running: Bool
    @State private var copied = false

    init(run: Run, onChange: @escaping () async -> Void) {
        self.run = run
        self.onChange = onChange
        _running = State(initialValue: run.running)
    }

    var body: some View {
        VStack(spacing: 0) {
            attachBar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { ChatBubble(item: $0).id($0.id) }
                    }
                    .padding()
                }
                .onChange(of: items.count) { _, _ in
                    if let last = items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .navigationTitle(run.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task { try? await app.client.killRun(name: run.name); await onChange() }
                } label: { Label("Kill", systemImage: "stop.circle") }
                .disabled(!running)
            }
        }
        .task { await pollLoop() }
    }

    private var attachBar: some View {
        HStack {
            Image(systemName: "terminal")
            Text(run.attach).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button {
                Clipboard.copy(run.attach); copied = true
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
            .buttonStyle(.borderless)
            HStack(spacing: 4) {
                Circle().fill(running ? .green : .secondary).frame(width: 8, height: 8)
                Text(running ? "running" : "finished").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    // Poll the log while running; one final load after it stops.
    private func pollLoop() async {
        await load()
        while running {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await load()
        }
    }

    private func load() async {
        guard let res = try? await app.client.runLog(name: run.name) else { return }
        items = ChatItem.list(from: res.events)
        // Reflect current running state from the runs list.
        if let fresh = try? await app.client.runs().first(where: { $0.name == run.name }) {
            running = fresh.running
        }
    }
}

enum Clipboard {
    static func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

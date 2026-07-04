import SwiftUI

// Live mirror of a Claude terminal running in tmux on the Mac. Polls the pane
// content continuously, so re-entering always shows the true current state —
// nothing to lose or replay. Types via send-keys.
struct TerminalView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    let term: TermSession

    @State private var content = ""
    @State private var draft = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            screen
            Divider()
            keyBar
            inputBar
        }
        .navigationTitle(term.projectName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Clipboard.copy(term.attach ?? ""); copied = true
                } label: { Image(systemName: copied ? "checkmark" : "terminal") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task { try? await app.client.killTerm(name: term.name); await manager.refreshTerminals(); manager.selection = nil }
                } label: { Image(systemName: "xmark.circle") }
            }
        }
        // Re-polls every time the view appears → always live on re-entry.
        .task(id: term.id) { await pollLoop() }
    }

    private var screen: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Text(content.isEmpty ? "connecting…" : content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .id("bottom")
            }
            .background(Color(white: 0.08))
            .onChange(of: content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var keyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                keyButton("esc", "Escape")
                keyButton("⏎", "Enter")
                keyButton("⌃C", "C-c")
                keyButton("↑", "Up")
                keyButton("↓", "Down")
                keyButton("⇧⇥", "S-Tab")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func keyButton(_ label: String, _ key: String) -> some View {
        Button(label) { Task { try? await app.client.sendKey(name: term.name, key: key); await load() } }
            .font(.caption.monospaced())
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type to Claude…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.assistantBubble, in: Capsule())
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { try? await app.client.sendTerm(name: term.name, text: text); await load() }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    private func load() async {
        if let c = try? await app.client.capture(name: term.name, lines: 80) { content = c }
    }
}

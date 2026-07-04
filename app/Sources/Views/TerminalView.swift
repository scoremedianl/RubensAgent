import SwiftUI

// Live mirror of a Claude terminal running in tmux on the Mac. State lives in
// SessionManager (which polls the selected terminal centrally and caches the
// output), so switching between terminals is instant and never gets stuck.
struct TerminalView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    let term: TermSession

    @State private var draft = ""
    @State private var copied = false
    @State private var didScroll = false

    private var content: String { manager.captures[term.name] ?? "" }
    private var everLoaded: Bool { manager.loadedTerms.contains(term.name) }
    private var isRunning: Bool { manager.term(term.name)?.running ?? true }

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
                Button { Clipboard.copy(term.attach ?? ""); copied = true } label: {
                    Image(systemName: copied ? "checkmark" : "terminal")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task {
                        try? await app.client.killTerm(name: term.name)
                        await manager.refreshTerminals()
                        manager.selection = nil
                    }
                } label: { Image(systemName: "xmark.circle") }
            }
        }
        // Capture immediately on open so the mirror shows at once.
        .task(id: term.id) {
            manager.startPolling()
            await manager.captureNow(term.name)
        }
    }

    @ViewBuilder private var screen: some View {
        if !content.isEmpty {
            terminalScroll
        } else if everLoaded || !isRunning {
            endedView
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Starting Claude…").font(.headline).foregroundStyle(.white)
            Text("Spinning up the terminal on your Mac — this can take a few seconds.")
                .font(.caption).foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    private var endedView: some View {
        ContentUnavailableView {
            Label("Session ended", systemImage: "xmark.circle")
        } description: {
            Text("This terminal is no longer running on the Mac.")
        } actions: {
            Button("Remove") {
                Task { try? await app.client.killTerm(name: term.name); await manager.refreshTerminals(); manager.selection = nil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    private var terminalScroll: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .id("bottom")
            }
            .background(Color(white: 0.08))
            // Scroll to the active area once; don't re-scroll on every poll
            // (that made the view jump around, badly on iPhone).
            .onChange(of: content) { _, new in
                guard !didScroll, !new.isEmpty else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
                didScroll = true
            }
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
        Button(label) {
            Task { try? await app.client.sendKey(name: term.name, key: key); await manager.captureNow(term.name) }
        }
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
        Task {
            try? await app.client.sendTerm(name: term.name, text: text)
            await manager.captureNow(term.name)
        }
    }
}

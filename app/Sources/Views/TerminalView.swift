import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

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
    @StateObject private var scroller = PageScroller()
    @State private var paging = false          // showing history, not the live tail
    @State private var showFileImporter = false
    @State private var attachedPath: String?
    @State private var attachedName: String?
    @State private var uploading = false
    @StateObject private var dictation = SpeechDictation()
    @State private var dictationPrefix = ""
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    private var content: String { manager.captures[term.name] ?? "" }
    private var everLoaded: Bool { manager.loadedTerms.contains(term.name) }
    private var isRunning: Bool { manager.term(term.name)?.running ?? true }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
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
            Text("Starting \(term.kind.label)…").font(.headline).foregroundStyle(.white)
            Text("Spinning up the terminal on your Mac — this can take a few seconds.")
                .font(.caption).foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    private var endedView: some View {
        ContentUnavailableView {
            Label("Session stopped", systemImage: "pause.circle")
        } description: {
            Text("Resume to continue this project's last conversation, or remove it.")
        } actions: {
            Button("Resume") { Task { await manager.resume(term.name) } }
                .buttonStyle(.borderedProminent)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .id("bottom")
            }
            .background(terminalBackground)
            // Scroll to the active area once; don't re-scroll on every poll
            // (that made the view jump around, badly on iPhone).
            .onChange(of: content) { _, new in
                guard !didScroll, !new.isEmpty else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
                didScroll = true
            }
            // The pane itself has no scrollback (alternate screen), so a swipe
            // or the wheel pages the agent's own view instead.
            .terminalPaging(scroller: scroller) { up in page(up) }
            .overlay(alignment: .bottomTrailing) { jumpToLive }
        }
    }

    private var terminalBackground: some View {
        LinearGradient(colors: [Color(white: 0.10), Color(white: 0.065)],
                       startPoint: .top, endPoint: .bottom)
    }

    // Only offered once you've actually paged away from the live tail.
    @ViewBuilder private var jumpToLive: some View {
        if paging {
            Button {
                paging = false
                Task {
                    // A few page-downs beat one: the TUI clamps at the bottom.
                    for _ in 0..<12 { try? await app.client.sendKey(name: term.name, key: "NPage") }
                    await manager.captureNow(term.name)
                }
            } label: {
                Label("Jump to live", systemImage: "arrow.down.to.line")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func page(_ up: Bool) {
        if up { paging = true }
        Task {
            try? await app.client.sendKey(name: term.name, key: up ? "PPage" : "NPage")
            await manager.captureNow(term.name)
        }
    }

    // Which agent and model this session runs, always visible.
    private var sessionHeader: some View {
        HStack(spacing: 8) {
            AgentGlyph(kind: term.kind, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(term.kind.label).font(.caption.weight(.semibold))
                Text(term.cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ModelChip(modelId: term.model, compact: true)
            if manager.term(term.name)?.busy == true {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }

    private var keyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                keyButton("esc", "Escape")
                keyButton("⏎", "Enter")
                keyButton("⌃C", "C-c")
                Divider().frame(height: 16)
                keyButton("⇞", "PPage")
                keyButton("⇟", "NPage")
                Divider().frame(height: 16)
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
            if key == "PPage" { paging = true }
            if key == "NPage" { paging = false }
            Task { try? await app.client.sendKey(name: term.name, key: key); await manager.captureNow(term.name) }
        }
        .font(.caption.monospaced())
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let name = attachedName {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip").font(.caption)
                    Text(name).font(.caption).lineLimit(1)
                    if uploading { ProgressView().controlSize(.small) }
                    Spacer()
                    Button { attachedPath = nil; attachedName = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accentSoft, in: Capsule())
            }
            HStack(spacing: 10) {
                attachControls
                TextField("Message \(term.kind.label)…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.assistantBubble, in: Capsule())
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? term.kind.tint : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(12)
        .background(.bar)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.image, .pdf, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importFile(url) }
        }
        .onChange(of: dictation.transcript) { _, t in
            draft = dictationPrefix + t
        }
        #if os(iOS)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await upload(data: data, name: "photo.jpg")
                }
            }
        }
        #endif
    }

    private var attachControls: some View {
        HStack(spacing: 8) {
            Button { toggleDictation() } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(dictation.isRecording ? .red : .secondary)
                    .symbolEffect(.pulse, isActive: dictation.isRecording)
            }
            .buttonStyle(.plain)
            #if os(iOS)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo").font(.title3).foregroundStyle(.secondary)
            }
            #endif
            Button { showFileImporter = true } label: {
                Image(systemName: "paperclip").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleDictation() {
        if !dictation.isRecording {
            dictationPrefix = draft.trimmingCharacters(in: .whitespaces).isEmpty ? "" : draft + " "
        }
        dictation.toggle()
    }

    private var canSend: Bool {
        !uploading && !(draft.trimmingCharacters(in: .whitespaces).isEmpty && attachedPath == nil)
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        Task { await upload(data: data, name: url.lastPathComponent) }
    }

    private func upload(data: Data, name: String) async {
        uploading = true
        attachedName = name
        defer { uploading = false }
        if let path = try? await app.client.uploadFile(filename: name, dataBase64: data.base64EncodedString()) {
            attachedPath = path
        } else {
            attachedName = nil
        }
    }

    private func send() {
        dictation.stop()
        let base = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = base
        if let path = attachedPath {
            text = base.isEmpty ? "Look at this file: \(path)" : "\(base) \(path)"
        }
        guard !text.isEmpty else { return }
        draft = ""; attachedPath = nil; attachedName = nil
        Task {
            try? await app.client.sendTerm(name: term.name, text: text)
            await manager.captureNow(term.name)
        }
    }
}

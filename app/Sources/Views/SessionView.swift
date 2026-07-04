import SwiftUI

struct SessionView: View {
    let entry: SessionEntry
    @ObservedObject var socket: SessionSocket
    @EnvironmentObject var manager: SessionManager
    @State private var draft = ""
    @State private var showAutoContinue = false

    init(entry: SessionEntry) {
        self.entry = entry
        _socket = ObservedObject(wrappedValue: entry.socket)
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            inputBar
        }
        .navigationTitle(entry.project.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                statusDot
                Button { showAutoContinue = true } label: { Image(systemName: "repeat") }
                Button(role: .destructive) { manager.close(entry.id) } label: { Image(systemName: "xmark.circle") }
            }
        }
        .sheet(isPresented: $showAutoContinue) {
            AutoContinueSheet { max, prompt, marker in
                socket.autoContinue(maxIterations: max, prompt: prompt, stopMarker: marker)
            }
        }
    }

    private var statusDot: some View {
        HStack(spacing: 4) {
            if socket.working {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(socket.connected ? .green : .secondary).frame(width: 8, height: 8)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(socket.items) { item in
                        ChatBubble(item: item).id(item.id)
                    }
                }
                .padding()
            }
            .onChange(of: socket.items.count) { _, _ in
                if let last = socket.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message Claude…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
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
        socket.sendText(draft)
        draft = ""
    }
}

struct ChatBubble: View {
    let item: ChatItem
    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCorner))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                avatar
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.assistantBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCorner))
                Spacer(minLength: 24)
            }
        case .tool:
            HStack(spacing: 6) {
                avatar.opacity(0)
                Label(item.text.replacingOccurrences(of: "🔧 ", with: ""), systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
                Spacer(minLength: 24)
            }
        case .toolResult:
            HStack(spacing: 6) {
                avatar.opacity(0)
                Text(item.text).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer(minLength: 24)
            }
        case .status:
            Text(item.text).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .error:
            Label(item.text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.red)
        }
    }

    private var avatar: some View {
        Circle().fill(Theme.accent)
            .frame(width: 22, height: 22)
            .overlay(Image(systemName: "sparkle").font(.caption2).foregroundStyle(.white))
    }
}

struct AutoContinueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var maxIterations = 5
    @State private var prompt = "Continue."
    @State private var marker = ""
    let onStart: (Int, String, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Max iterations: \(maxIterations)", value: $maxIterations, in: 1...50)
                TextField("Continue prompt", text: $prompt).textFieldStyle(.roundedBorder)
                TextField("Stop when output contains… (optional)", text: $marker).textFieldStyle(.roundedBorder)
            }
            .navigationTitle("Auto-continue")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(maxIterations, prompt, marker.isEmpty ? nil : marker)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

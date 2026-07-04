import SwiftUI

struct SessionView: View {
    @EnvironmentObject var app: AppState
    let project: Project
    let resumeId: String?
    let autoApprove: Bool

    @StateObject private var socket: SessionSocket
    @State private var draft = ""
    @State private var started = false
    @State private var showAutoContinue = false

    init(project: Project, resumeId: String?, autoApprove: Bool) {
        self.project = project
        self.resumeId = resumeId
        self.autoApprove = autoApprove
        // SessionSocket needs connection details up front; read from defaults.
        let host = UserDefaults.standard.string(forKey: "bridge.host") ?? ""
        let port = UserDefaults.standard.integer(forKey: "bridge.port")
        let token = UserDefaults.standard.string(forKey: "bridge.token") ?? ""
        _socket = StateObject(wrappedValue: SessionSocket(host: host, port: port == 0 ? 8787 : port, token: token))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            inputBar
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItemGroup {
                if socket.working { ProgressView().controlSize(.small) }
                Button { showAutoContinue = true } label: { Image(systemName: "repeat") }
                Button(role: .destructive) { socket.stop() } label: { Image(systemName: "stop.circle") }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            socket.start(cwd: project.path, resumeId: resumeId, autoApprove: autoApprove)
        }
        .sheet(isPresented: $showAutoContinue) {
            AutoContinueSheet { max, prompt, marker in
                socket.autoContinue(maxIterations: max, prompt: prompt, stopMarker: marker)
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
        HStack(spacing: 8) {
            TextField("Message Claude…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit(send)
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
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
            bubble(item.text, bg: Color.accentColor.opacity(0.15), align: .trailing)
        case .assistant:
            bubble(item.text, bg: Color.gray.opacity(0.12), align: .leading)
        case .tool:
            Text(item.text).font(.caption.monospaced()).foregroundStyle(.blue)
        case .toolResult:
            Text(item.text).font(.caption.monospaced()).foregroundStyle(.secondary)
        case .status:
            Text(item.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
        case .error:
            Text(item.text).font(.callout).foregroundStyle(.red)
        }
    }

    private func bubble(_ text: String, bg: Color, align: HorizontalAlignment) -> some View {
        HStack {
            if align == .trailing { Spacer(minLength: 40) }
            Text(text)
                .textSelection(.enabled)
                .padding(10)
                .background(bg, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: align == .trailing ? .trailing : .leading)
            if align == .leading { Spacer(minLength: 40) }
        }
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

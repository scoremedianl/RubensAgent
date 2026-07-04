import Foundation

// Live Claude session over the bridge's WebSocket. Owns the chat transcript
// as it streams in. One instance per open session view.
@MainActor
final class SessionSocket: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var connected = false
    @Published var sessionId: String?
    @Published var working = false          // true while a turn is in flight
    @Published var lastError: String?

    private var task: URLSessionWebSocketTask?
    private let host: String
    private let port: Int
    private let token: String

    init(host: String, port: Int, token: String) {
        self.host = host; self.port = port; self.token = token
    }

    // Start a fresh session in `cwd`, or resume `resumeId` if given.
    func start(cwd: String, resumeId: String? = nil,
               permissionMode: String = "bypassPermissions", model: String = "") {
        connect()
        var msg: [String: Any] = ["type": "start", "cwd": cwd, "permissionMode": permissionMode]
        if let resumeId { msg["resumeId"] = resumeId }
        if !model.isEmpty { msg["model"] = model }
        working = true
        sendJSON(msg)
    }

    // Re-join a session that is still running on the daemon: load the
    // conversation so far, then subscribe to live events.
    func attach(cwd: String, sessionId: String) {
        self.sessionId = sessionId
        connect()
        Task {
            if let events = try? await Bridge.client.transcript(cwd: cwd, id: sessionId) {
                items = ChatItem.list(from: events)
            }
            sendJSON(["type": "attach", "id": sessionId])
        }
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(ChatItem(kind: .user, text: trimmed))
        working = true
        sendJSON(["type": "input", "text": trimmed])
    }

    func autoContinue(maxIterations: Int, prompt: String, stopMarker: String?) {
        var m: [String: Any] = ["type": "auto-continue", "maxIterations": maxIterations, "continuePrompt": prompt]
        if let stopMarker { m["stopMarker"] = stopMarker }
        sendJSON(m)
        items.append(ChatItem(kind: .status, text: "Auto-continue: max \(maxIterations)×"))
    }

    func stop() {
        sendJSON(["type": "stop"])
        task?.cancel(with: .goingAway, reason: nil)
        connected = false
    }

    // MARK: - transport

    private func connect() {
        guard task == nil else { return }
        let q = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        guard let url = URL(string: "ws://\(host):\(port)/ws?token=\(q)") else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        connected = true
        receiveLoop()
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { [weak self] err in
            if let err { Task { @MainActor in self?.lastError = err.localizedDescription } }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let err):
                    self.connected = false
                    self.lastError = err.localizedDescription
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let probe = try? JSONDecoder().decode(TypeProbe.self, from: data) else { return }
        let dec = JSONDecoder()
        switch probe.type {
        case "session":
            if let env = try? dec.decode(IdEnvelope.self, from: data) { sessionId = env.id ?? sessionId }
        case "event":
            if let env = try? dec.decode(EventEnvelope.self, from: data) { handleEvent(env.data) }
        case "stderr", "error":
            if let env = try? dec.decode(StringDataEnvelope.self, from: data), let d = env.data, !d.isEmpty {
                if probe.type == "error" { items.append(ChatItem(kind: .error, text: d)) }
            }
        case "exit":
            connected = false
            working = false
            items.append(ChatItem(kind: .status, text: "Session ended"))
        default:
            break
        }
    }

    private func handleEvent(_ e: StreamEvent) {
        switch e.type {
        case "assistant":
            for block in e.message?.content ?? [] {
                switch block.type {
                case "text":
                    if let t = block.text, !t.isEmpty { items.append(ChatItem(kind: .assistant, text: t)) }
                case "tool_use":
                    items.append(ChatItem(kind: .tool, text: "🔧 \(block.name ?? "tool")"))
                default: break
                }
            }
        case "result":
            working = false
            if e.is_error == true {
                items.append(ChatItem(kind: .error, text: e.result ?? "error"))
            }
        default:
            break
        }
    }
}

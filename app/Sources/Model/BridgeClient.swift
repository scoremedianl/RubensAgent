import Foundation

// REST client for the bridge daemon. Pure networking; callers marshal to the UI.
struct BridgeClient {
    var host: String
    var port: Int
    var token: String

    private var base: URL { URL(string: "http://\(host):\(port)")! }

    enum ClientError: LocalizedError {
        case http(Int, String)
        case badURL
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .badURL: return "Bad URL"
            }
        }
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base) else { throw ClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClientError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func health() async throws -> Health {
        try JSONDecoder().decode(Health.self, from: await request("/health"))
    }
    func projects() async throws -> [Project] {
        try JSONDecoder().decode(ProjectsResponse.self, from: await request("/projects")).projects
    }
    func availableRepos() async throws -> AvailableReposResponse {
        try JSONDecoder().decode(AvailableReposResponse.self, from: await request("/projects/available"))
    }
    func clone(_ name: String) async throws {
        _ = try await request("/projects/clone", method: "POST", body: ["name": name])
    }
    func persistedSessions(cwd: String) async throws -> [PersistedSession] {
        let q = cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cwd
        return try JSONDecoder().decode(PersistedSessionsResponse.self,
                                        from: await request("/sessions/persisted?cwd=\(q)")).sessions
    }
    func loops() async throws -> [Loop] {
        try JSONDecoder().decode(LoopsResponse.self, from: await request("/loops")).loops
    }
    func usage() async throws -> Usage {
        try JSONDecoder().decode(Usage.self, from: await request("/usage"))
    }
    func claudeUsage() async throws -> ClaudeUsage {
        try JSONDecoder().decode(ClaudeUsage.self, from: await request("/usage/claude"))
    }
    func memoryFiles() async throws -> [MemoryFile] {
        try JSONDecoder().decode(MemoryFilesResponse.self, from: await request("/memory")).files
    }
    func memoryContent(_ name: String) async throws -> String {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return try JSONDecoder().decode(MemoryContentResponse.self,
                                        from: await request("/memory/file?name=\(q)")).content
    }
    func saveMemory(_ name: String, content: String) async throws {
        _ = try await request("/memory/file", method: "PUT", body: ["name": name, "content": content])
    }
    func system() async throws -> SystemStats {
        try JSONDecoder().decode(SystemStats.self, from: await request("/system"))
    }
    func accessibleRepos(search: String) async throws -> ReposResponse {
        let q = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try JSONDecoder().decode(ReposResponse.self, from: await request("/repos?search=\(q)"))
    }
    func cloneAccessible(fullName: String) async throws {
        _ = try await request("/repos/clone", method: "POST", body: ["fullName": fullName])
    }
    func createFolder(name: String) async throws {
        _ = try await request("/projects/create", method: "POST", body: ["name": name])
    }
    func runs() async throws -> [Run] {
        try JSONDecoder().decode(RunsResponse.self, from: await request("/runs")).runs
    }
    func startRun(cwd: String, prompt: String, model: String, permissionMode: String) async throws -> Run {
        var body: [String: Any] = ["cwd": cwd, "prompt": prompt, "permissionMode": permissionMode]
        if !model.isEmpty { body["model"] = model }
        return try JSONDecoder().decode(Run.self, from: await request("/runs", method: "POST", body: body))
    }
    func runLog(name: String) async throws -> RunLogResponse {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return try JSONDecoder().decode(RunLogResponse.self, from: await request("/runs/log?name=\(q)"))
    }
    func killRun(name: String) async throws {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        _ = try await request("/runs?name=\(q)", method: "DELETE")
    }
    // Interactive terminal sessions (tmux-mirrored).
    func startTerm(cwd: String, model: String) async throws -> TermSession {
        var body: [String: Any] = ["cwd": cwd]
        if !model.isEmpty { body["model"] = model }
        return try JSONDecoder().decode(TermSession.self, from: await request("/term/start", method: "POST", body: body))
    }
    func terms() async throws -> [TermSession] {
        try JSONDecoder().decode(TermListResponse.self, from: await request("/term/list")).terms
    }
    func capture(name: String, lines: Int = 60) async throws -> String {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return try JSONDecoder().decode(TermCapture.self, from: await request("/term/capture?name=\(q)&lines=\(lines)")).content
    }
    func sendTerm(name: String, text: String) async throws {
        _ = try await request("/term/send", method: "POST", body: ["name": name, "text": text])
    }
    func sendKey(name: String, key: String) async throws {
        _ = try await request("/term/key", method: "POST", body: ["name": name, "key": key])
    }
    // Upload an attachment/photo to the Mac; returns its path to reference in chat.
    func uploadFile(filename: String, dataBase64: String) async throws -> String {
        let data = try await request("/term/upload", method: "POST",
                                     body: ["filename": filename, "dataBase64": dataBase64])
        return try JSONDecoder().decode(UploadResult.self, from: data).path
    }
    func killTerm(name: String) async throws {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        _ = try await request("/term?name=\(q)", method: "DELETE")
    }
    func liveSessions() async throws -> [SessionInfo] {
        try JSONDecoder().decode(LiveSessionsResponse.self, from: await request("/sessions")).sessions
    }
    func branches(cwd: String) async throws -> BranchInfo {
        let q = cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cwd
        return try JSONDecoder().decode(BranchInfo.self, from: await request("/projects/git/branches?cwd=\(q)"))
    }
    func gitPull(cwd: String) async throws {
        _ = try await request("/projects/git/pull", method: "POST", body: ["cwd": cwd])
    }
    func gitCheckout(cwd: String, branch: String, hard: Bool = false) async throws {
        _ = try await request("/projects/git/checkout", method: "POST",
                              body: ["cwd": cwd, "branch": branch, "hard": hard])
    }
    func transcript(cwd: String, id: String) async throws -> [StreamEvent] {
        let qc = cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cwd
        let qi = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try JSONDecoder().decode(TranscriptResponse.self,
                                        from: await request("/transcript?cwd=\(qc)&id=\(qi)")).messages
    }
    func addLoop(cwd: String, schedule: String, prompt: String, project: String?, autoApprove: Bool) async throws {
        var body: [String: Any] = ["type": "cron", "cwd": cwd, "schedule": schedule,
                                   "prompt": prompt, "autoApprove": autoApprove]
        if let project { body["project"] = project }
        _ = try await request("/loops", method: "POST", body: body)
    }
    func deleteLoop(_ id: String) async throws {
        _ = try await request("/loops/\(id)", method: "DELETE")
    }
    func setLoopEnabled(_ id: String, _ enabled: Bool) async throws {
        _ = try await request("/loops/\(id)/enable", method: "POST", body: ["enabled": enabled])
    }
    func runLoop(_ id: String) async throws {
        _ = try await request("/loops/\(id)/run", method: "POST")
    }
}

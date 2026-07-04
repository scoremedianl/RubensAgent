import Foundation

// MARK: - REST models (match the daemon's JSON)

struct Project: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    var branch: String?
    var remote: String?
    var lastCommit: String?
}

struct ProjectsResponse: Codable { let projects: [Project] }

struct AvailableRepo: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sshUrl: String?
    let pushedAt: String?
    let description: String?
}
struct AvailableReposResponse: Codable {
    let available: [AvailableRepo]
    let ghAuthenticated: Bool
}

struct PersistedSession: Codable, Identifiable, Hashable {
    let id: String
    let modified: String
    let sizeBytes: Int
}
struct PersistedSessionsResponse: Codable { let sessions: [PersistedSession] }

struct Health: Codable { let ok: Bool; let version: String; let projectsDir: String }

struct Loop: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let schedule: String
    let project: String?
    let cwd: String
    let prompt: String
    let autoApprove: Bool
    let enabled: Bool
    var lastRun: String?
    var lastStatus: String?
    var lastSummary: String?
    var lastSessionId: String?
}
struct LoopsResponse: Codable { let loops: [Loop] }

// MARK: - stream-json event models (Claude Code output)

struct StreamEvent: Decodable {
    let type: String
    let subtype: String?
    let session_id: String?
    let message: EventMessage?
    let result: String?
    let total_cost_usd: Double?
    let duration_ms: Int?
    let is_error: Bool?
}

struct EventMessage: Decodable {
    let role: String?
    let content: [ContentBlock]?
}

struct ContentBlock: Decodable {
    let type: String
    let text: String?
    let name: String?          // tool_use
    let tool_use_id: String?   // tool_result
}

// MARK: - WebSocket envelope probes (from the bridge)

struct TypeProbe: Decodable { let type: String }
struct EventEnvelope: Decodable { let data: StreamEvent }
struct IdEnvelope: Decodable { let id: String?; let key: String? }
struct StringDataEnvelope: Decodable { let data: String? }

// MARK: - Chat view model

struct ChatItem: Identifiable, Hashable {
    enum Kind: Hashable { case user, assistant, tool, toolResult, status, error }
    let id = UUID()
    var kind: Kind
    var text: String
}

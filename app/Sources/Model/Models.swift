import Foundation

// MARK: - REST models (match the daemon's JSON)

struct Project: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    var branch: String? = nil
    var remote: String? = nil
    var lastCommit: String? = nil
    var lastActivity: String? = nil
    var git: Bool = true
}

struct ProjectsResponse: Codable { let projects: [Project] }

struct SessionInfo: Codable, Identifiable, Hashable {
    let id: String
    let project: String?
    let cwd: String
    let permissionMode: String?
    let startedAt: String?
    let alive: Bool
}
struct LiveSessionsResponse: Codable { let sessions: [SessionInfo] }

struct BranchInfo: Codable { let current: String; let branches: [String] }

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

// MARK: - Usage / limits

struct RateLimitInfo: Codable, Hashable {
    let status: String?
    let resetsAt: Double?
    let rateLimitType: String?
    let isUsingOverage: Bool?
    let overageStatus: String?
}
struct RateLimitEnvelope: Codable, Hashable {
    let rate_limit_info: RateLimitInfo?
}
struct Usage: Codable {
    let totalCostUsd: Double
    let turns: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let lastRateLimit: RateLimitEnvelope?
    let updatedAt: String?
}

// MARK: - Memory files

struct MemoryFile: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let root: Bool
    let sizeBytes: Int
}
struct MemoryFilesResponse: Codable { let files: [MemoryFile] }
struct MemoryContentResponse: Codable { let name: String; let content: String }

struct TranscriptResponse: Decodable { let messages: [StreamEvent] }

// MARK: - Persistent tmux runs

struct Run: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let cwd: String
    let prompt: String
    let model: String?
    let permissionMode: String
    let startedAt: String
    let running: Bool
    let attach: String
    let logSize: Int?
}
struct RunsResponse: Codable { let runs: [Run] }
struct RunLogResponse: Decodable { let name: String; let raw: String; let events: [StreamEvent] }

// MARK: - Interactive terminal sessions (tmux-mirrored)

struct TermSession: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let cwd: String
    let model: String?
    let startedAt: String
    var running: Bool = true
    let attach: String?

    var projectName: String { (cwd as NSString).lastPathComponent }
}
struct TermListResponse: Codable { let terms: [TermSession] }
struct TermCapture: Codable { let name: String; let content: String }

// MARK: - System stats

struct ThermalInfo: Codable, Hashable { let cpuSpeedLimit: Int?; let throttling: Bool }
struct SystemStats: Codable {
    let chip: String
    let model: String
    let hostname: String
    let cores: Int
    let performanceCores: Int?
    let efficiencyCores: Int?
    let totalRamBytes: Int
    let macos: String?
    let cpuPercent: Double?
    let load1: Double?
    let memUsedBytes: Int?
    let memPercent: Double?
    let uptimeSeconds: Int
    let thermal: ThermalInfo
    var tempCpu: Double? = nil
    var tempGpu: Double? = nil
}

// MARK: - Repo browser

struct Repo: Codable, Identifiable, Hashable {
    var id: String { fullName }
    let fullName: String
    let name: String
    let owner: String
    let sshUrl: String?
    let pushedAt: String?
    let description: String?
    let isPrivate: Bool
    let cloned: Bool

    enum CodingKeys: String, CodingKey {
        case fullName, name, owner, sshUrl, pushedAt, description
        case isPrivate = "private"
        case cloned
    }
}
struct ReposResponse: Codable { let repos: [Repo]; let ghAuthenticated: Bool }

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

    // Convert raw transcript / stream events into chat bubbles.
    static func list(from events: [StreamEvent]) -> [ChatItem] {
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

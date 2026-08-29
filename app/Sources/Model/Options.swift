import Foundation
import SwiftUI

// Permission behaviour for a session, chosen per session (and per loop).
enum PermissionMode: String, CaseIterable, Identifiable {
    case ask = "default"
    case acceptEdits = "acceptEdits"
    case bypass = "bypassPermissions"
    case plan = "plan"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: return "Ask on changes"
        case .acceptEdits: return "Auto-edit, ask rest"
        case .bypass: return "Full auto"
        case .plan: return "Plan only (read-only)"
        }
    }
    var detail: String {
        switch self {
        case .ask: return "Claude asks before edits & commands"
        case .acceptEdits: return "Edits auto-approved, other tools ask"
        case .bypass: return "Runs everything without asking"
        case .plan: return "Explores and plans, makes no changes"
        }
    }
}

// The coding agents the bridge can run in a tmux terminal. Must match the ids
// in the daemon's agents.mjs registry.
enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case claude
    case opencode
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .opencode: return "OpenCode"
        case .codex: return "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkles"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .codex: return "circle.hexagongrid"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return Theme.accent
        case .opencode: return .teal
        case .codex: return .green
        }
    }

    // What to tell the user when the daemon reports the agent isn't ready.
    var loginHint: String {
        switch self {
        case .claude: return "Sign in with `claude` on the Mac."
        case .opencode: return "Run `opencode auth login` on the Mac."
        case .codex: return "Run `codex login` on the Mac."
        }
    }

    // Models offered in the picker. Claude has a fixed preset list; OpenCode
    // reports its own via `opencode models` (merged in at runtime); Codex has
    // no list command, so you pick the model inside its TUI with /model.
    var staticModels: [ModelOption] {
        switch self {
        case .claude:
            return [
                ModelOption(id: "", label: "Default"),
                ModelOption(id: "claude-opus-5", label: "Opus 5"),
                ModelOption(id: "claude-opus-4-8", label: "Opus 4.8"),
                ModelOption(id: "claude-sonnet-5", label: "Sonnet 5"),
                ModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5"),
                ModelOption(id: "claude-fable-5", label: "Fable 5"),
            ]
        case .opencode, .codex:
            return [ModelOption(id: "", label: "Default")]
        }
    }
}

// Model presets for the picker. Empty id = account default.
struct ModelOption: Identifiable, Hashable {
    let id: String
    let label: String
}

// Kept for the older chat/loop code paths that still reference it.
let modelOptions: [ModelOption] = AgentKind.claude.staticModels

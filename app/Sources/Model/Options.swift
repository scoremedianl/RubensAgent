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
        case .claude: return "sparkle"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .codex: return "hexagon.fill"
        }
    }

    /// Each agent gets its own colour so a glance at the sidebar tells you
    /// which one is running where.
    var tint: Color {
        switch self {
        case .claude: return Theme.accent          // Claude clay
        case .opencode: return Color(red: 0.29, green: 0.65, blue: 0.62)
        case .codex: return Color(red: 0.10, green: 0.72, blue: 0.51)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.65)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var blurb: String {
        switch self {
        case .claude: return "Anthropic · terminal agent"
        case .opencode: return "Open source · bring your own provider"
        case .codex: return "OpenAI · ChatGPT account"
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

    /// Provider prefix of an OpenCode-style "provider/model" id, if any.
    var provider: String? {
        let parts = id.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }
}

// A small visual identity per model family, so the picker and the session
// header read at a glance instead of being a wall of identical rows.
enum ModelFamily {
    case opus, sonnet, haiku, fable, gpt, gemini, llama, other, deflt

    static func of(_ id: String) -> ModelFamily {
        if id.isEmpty { return .deflt }
        let s = id.lowercased()
        if s.contains("opus") { return .opus }
        if s.contains("sonnet") { return .sonnet }
        if s.contains("haiku") { return .haiku }
        if s.contains("fable") { return .fable }
        if s.contains("gpt") || s.contains("o1") || s.contains("o3") || s.contains("codex") { return .gpt }
        if s.contains("gemini") { return .gemini }
        if s.contains("llama") || s.contains("mistral") || s.contains("qwen") || s.contains("deepseek") { return .llama }
        return .other
    }

    var symbol: String {
        switch self {
        case .opus: return "brain.head.profile"
        case .sonnet: return "wand.and.stars"
        case .haiku: return "bolt.fill"
        case .fable: return "book.pages"
        case .gpt: return "circle.hexagonpath.fill"
        case .gemini: return "diamond.fill"
        case .llama: return "cube.transparent"
        case .other: return "cpu"
        case .deflt: return "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .opus: return Color(red: 0.55, green: 0.36, blue: 0.78)
        case .sonnet: return Color(red: 0.85, green: 0.47, blue: 0.28)
        case .haiku: return Color(red: 0.94, green: 0.72, blue: 0.20)
        case .fable: return Color(red: 0.36, green: 0.55, blue: 0.85)
        case .gpt: return Color(red: 0.10, green: 0.72, blue: 0.51)
        case .gemini: return Color(red: 0.29, green: 0.51, blue: 0.90)
        case .llama: return Color(red: 0.80, green: 0.42, blue: 0.55)
        case .other: return .secondary
        case .deflt: return .secondary
        }
    }
}

// Kept for the older chat/loop code paths that still reference it.
let modelOptions: [ModelOption] = AgentKind.claude.staticModels

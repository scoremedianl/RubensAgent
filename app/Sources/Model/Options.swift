import Foundation

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

// Model presets for the picker. Empty id = account default.
struct ModelOption: Identifiable, Hashable {
    let id: String
    let label: String
}

let modelOptions: [ModelOption] = [
    ModelOption(id: "", label: "Default"),
    ModelOption(id: "claude-opus-4-8", label: "Opus 4.8"),
    ModelOption(id: "claude-sonnet-5", label: "Sonnet 5"),
    ModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5"),
    ModelOption(id: "claude-fable-5", label: "Fable 5"),
]

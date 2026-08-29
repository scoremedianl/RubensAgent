import SwiftUI

// Small reusable identity pieces. Which agent and which model a session runs
// are the two facts you want to read at a glance, everywhere they appear — the
// sidebar, the session header, the pickers — so they get one shared look.

/// A filled, tinted glyph for an agent. Sized for lists (18) or headers (28).
struct AgentGlyph: View {
    let kind: AgentKind
    var size: CGFloat = 18
    var active: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(active ? AnyShapeStyle(kind.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(kind.label)
    }
}

/// Agent name with its glyph, for rows and headers.
struct AgentChip: View {
    let kind: AgentKind
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            AgentGlyph(kind: kind, size: compact ? 14 : 18)
            Text(kind.label)
                .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(kind.tint)
        }
    }
}

/// The model a session runs, coloured by family. Falls back to "Default".
struct ModelChip: View {
    let modelId: String?
    var compact = false

    private var id: String { modelId ?? "" }
    private var family: ModelFamily { ModelFamily.of(id) }
    private var label: String { ModelChip.prettyName(id) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: family.symbol)
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
            Text(label)
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
        }
        .foregroundStyle(family.tint)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(family.tint.opacity(0.12), in: Capsule())
    }

    // "claude-opus-5" -> "Opus 5"; "openrouter/anthropic/claude-3" -> "claude-3".
    static func prettyName(_ id: String) -> String {
        guard !id.isEmpty else { return "Default" }
        let tail = id.split(separator: "/").last.map(String.init) ?? id
        let cleaned = tail
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " 20")
        return cleaned
            .split(separator: "-")
            .map { $0.count <= 2 ? String($0) : $0.capitalized }
            .joined(separator: " ")
    }
}

/// An agent glyph carrying its own status badge. One leading element, instead
/// of a status dot *and* an icon competing for the same corner of every row.
struct AgentAvatar: View {
    let kind: AgentKind
    let running: Bool
    var size: CGFloat = 26

    var body: some View {
        AgentGlyph(kind: kind, size: size, active: running)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(running ? Color.green : Color.secondary)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .overlay(Circle().strokeBorder(rowBackground, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
    }

    private var rowBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
}

/// Short relative time ("3m", "2h") for list subtitles.
enum RelativeTime {
    static func short(_ iso: String?) -> String? {
        guard let iso, let d = parse(iso) else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// "29 Aug, 18:52" — readable where a raw ISO string used to be printed.
    static func friendly(_ iso: String?) -> String {
        guard let iso, let d = parse(iso) else { return iso ?? "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }

    /// The daemon sends fractional seconds; the default parser rejects those,
    /// so try with and without.
    private static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

/// A large, tappable agent card used to pick the agent for a new session.
struct AgentCard: View {
    let kind: AgentKind
    let status: AgentInfo?
    let selected: Bool
    let action: () -> Void

    private var usable: Bool { status?.usable ?? false }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                AgentGlyph(kind: kind, size: 30, active: usable)
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(usable ? .primary : .secondary)
                    .lineLimit(1)
                statusLine
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? kind.tint.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? kind.tint : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusLine: some View {
        if status == nil {
            Text("checking…").font(.caption2).foregroundStyle(.secondary)
        } else if !(status!.installed) {
            Label("not installed", systemImage: "xmark.circle.fill")
                .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleOnly)
        } else if status!.authKnown == false {
            Label("unknown", systemImage: "questionmark.circle")
                .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleOnly)
        } else if !(status!.authenticated) {
            Text("sign in").font(.caption2).foregroundStyle(.orange)
        } else {
            Text("ready").font(.caption2).foregroundStyle(.green)
        }
    }
}

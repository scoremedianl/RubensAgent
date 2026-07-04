import SwiftUI

// Central visual identity — a warm, Claude-like palette applied across the app.
enum Theme {
    // Claude "clay" accent.
    static let accent = Color(red: 0.788, green: 0.392, blue: 0.259)   // ~#C96442
    static let accentSoft = accent.opacity(0.14)

    // Chat bubbles.
    static let userBubble = accent.opacity(0.16)
    static let assistantBubble = Color.primary.opacity(0.055)

    // Surfaces.
    static let cardCorner: CGFloat = 14
    static let bubbleCorner: CGFloat = 16

    // A subtle warm wash for large surfaces (adapts to light/dark).
    static var warmWash: Color {
        Color(.sRGB, red: 0.82, green: 0.55, blue: 0.40, opacity: 0.05)
    }
}

// Soft card styling for grouped content.
struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.assistantBubble, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}
extension View {
    func card() -> some View { modifier(Card()) }
}

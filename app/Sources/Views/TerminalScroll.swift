import SwiftUI
#if os(macOS)
import AppKit
#endif

// Scrolling a mirrored agent terminal.
//
// These TUIs run in tmux's *alternate screen*, which has no scrollback at all —
// `capture-pane -S -400` returns exactly the same 42 visible lines. So there is
// nothing for the app to scroll through: the history lives inside the agent's
// own UI. The way to see earlier output is the way you would in a real
// terminal — press Page Up and let the TUI redraw. Verified against Claude
// Code's TUI: PPage scrolls back, NPage returns to the bottom.
//
// This turns natural gestures into those key presses: a swipe on iOS, the
// scroll wheel / trackpad on macOS, plus explicit buttons in the key bar.

/// Turns continuous scroll or drag distance into discrete page steps.
@MainActor
final class PageScroller: ObservableObject {
    /// Points of travel that make one page.
    private let threshold: CGFloat = 60
    /// Never send pages faster than the terminal can redraw and be re-captured.
    private let minInterval: TimeInterval = 0.12

    private var accumulated: CGFloat = 0
    private var lastAbsolute: CGFloat = 0
    private var lastSent = Date.distantPast

    /// Feed an *incremental* delta. Positive = show older output (page up).
    func feed(_ delta: CGFloat, onPage: (Bool) -> Void) {
        accumulated += delta
        while abs(accumulated) >= threshold {
            let up = accumulated > 0
            accumulated += up ? -threshold : threshold
            guard Date().timeIntervalSince(lastSent) >= minInterval else {
                accumulated = 0
                return
            }
            lastSent = Date()
            onPage(up)
        }
    }

    /// Feed a gesture's *cumulative* translation; the delta is derived here.
    /// DragGesture reports total travel on every change, not the step.
    func feedCumulative(_ total: CGFloat, onPage: (Bool) -> Void) {
        let delta = total - lastAbsolute
        lastAbsolute = total
        feed(delta, onPage: onPage)
    }

    /// Call when a gesture ends so the next one starts from zero.
    func reset() {
        accumulated = 0
        lastAbsolute = 0
    }
}

#if os(macOS)
/// Reports scroll-wheel deltas while the pointer is over this view.
///
/// A local event monitor rather than an overlay NSView on purpose: an overlay
/// that is hit-testable would swallow clicks and kill text selection in the
/// terminal, and one that isn't hit-testable never receives scrollWheel at all.
/// Gating a monitor on hover keeps selection working and still feels native.
private struct ScrollWheelReader: ViewModifier {
    let onScroll: (CGFloat) -> Void
    @State private var hovering = false
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active = phase { hovering = true } else { hovering = false }
            }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard hovering else { return event }
                    onScroll(event.scrollingDeltaY)
                    return nil   // consume, so the empty ScrollView doesn't also react
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
#endif

extension View {
    /// Make a mirrored terminal page through its own history with natural
    /// gestures. `onPage(true)` means page up (older output).
    @ViewBuilder
    func terminalPaging(scroller: PageScroller, onPage: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        self.modifier(ScrollWheelReader { delta in
            // Natural direction: wheel down (negative delta) shows newer text.
            scroller.feed(delta, onPage: onPage)
        })
        #else
        self.simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { scroller.feedCumulative($0.translation.height, onPage: onPage) }
                .onEnded { _ in scroller.reset() }
        )
        #endif
    }
}

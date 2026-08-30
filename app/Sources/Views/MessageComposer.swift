import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The message field.
//
// SwiftUI's `TextField(axis: .vertical)` re-measures the entire string on every
// change, so pasting a stack trace or a log freezes the app for as long as it
// takes to lay out tens of thousands of characters. A real text view is backed
// by a text container that only lays out what's on screen, and handles
// megabytes without noticing.
//
// It also reports large pastes instead of inserting them: a 1500-line log
// dumped into a four-line box is unreadable and tells you nothing. Those go
// into a compact attachment chip — the same thing all three agent TUIs do with
// a bracketed paste on the other end.
struct MessageComposer: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onLargePaste: (String) -> Void

    @State private var height: CGFloat = 22

    /// Grown-to-fit, but never taller than this — then it scrolls.
    private let maxHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            ComposerTextView(text: $text, height: $height,
                             maxHeight: maxHeight,
                             onSubmit: onSubmit, onLargePaste: onLargePaste)
                .frame(height: min(max(height, 22), maxHeight))
        }
    }
}

/// A block of pasted text held aside, shown as a chip rather than inline.
struct PastedBlock: Identifiable, Equatable {
    let id = UUID()
    let text: String

    var lines: Int { text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 } }
    var summary: String {
        let chars = text.count
        let size = chars > 1000 ? "\(chars / 1000)k characters" : "\(chars) characters"
        return lines > 1 ? "\(lines) lines · \(size)" : size
    }
    /// First non-empty line, for a hint of what it is.
    var firstLine: String {
        text.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

struct PastedBlockChip: View {
    let block: PastedBlock
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text.fill")
                .font(.caption)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pasted text").font(.caption.weight(.semibold))
                Text(block.summary).font(.caption2).foregroundStyle(.secondary)
            }
            if !block.firstLine.isEmpty {
                Text(block.firstLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Platform text view

/// Anything this big arriving in one edit is a paste, not typing.
private let largePasteChars = 700
private let largePasteLines = 8

#if os(macOS)
private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void
    let onLargePaste: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = NSSize(width: 1, height: 3)
        view.isRichText = false
        view.allowsUndo = true
        context.coordinator.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
        context.coordinator.recomputeHeight(view)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ComposerTextView
        weak var textView: NSTextView?
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            recomputeHeight(view)
        }

        // Enter sends; Shift+Enter (or Option+Enter) inserts a newline.
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                view.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            parent.onSubmit()
            return true
        }

        func textView(_ view: NSTextView,
                      shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard let incoming = replacementString, isLargePaste(incoming) else { return true }
            parent.onLargePaste(incoming)
            return false     // keep it out of the editor entirely
        }

        func recomputeHeight(_ view: NSTextView) {
            guard let container = view.textContainer, let manager = view.layoutManager else { return }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container).height + 6
            let clamped = min(max(used, 22), parent.maxHeight)
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}
#else
private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void
    let onLargePaste: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 3, left: 1, bottom: 3, right: 1)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        context.coordinator.recomputeHeight(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: ComposerTextView
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            recomputeHeight(view)
        }

        func textView(_ view: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if isLargePaste(text) {
                parent.onLargePaste(text)
                return false
            }
            return true
        }

        func recomputeHeight(_ view: UITextView) {
            let fitting = view.sizeThatFits(
                CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
            let clamped = min(max(fitting, 22), parent.maxHeight)
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}
#endif

private func isLargePaste(_ s: String) -> Bool {
    if s.count >= largePasteChars { return true }
    var newlines = 0
    for ch in s where ch == "\n" {
        newlines += 1
        if newlines >= largePasteLines { return true }
    }
    return false
}

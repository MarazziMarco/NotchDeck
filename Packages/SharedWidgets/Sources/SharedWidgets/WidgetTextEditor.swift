import AppKit
import SwiftUI

/// Explicit AppKit colors keep text, caret and background legible in transparent windows.
public struct WidgetTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let ink: NSColor
    private let paper: NSColor
    private let font: NSFont
    private let placeholder: String
    private let editable: Bool
    private let onEditingChange: (Bool) -> Void
    public init(text: Binding<String>, placeholder: String = "", ink: NSColor = .white, paper: NSColor = .clear,
                font: NSFont = .systemFont(ofSize: 14), editable: Bool = true,
                onEditingChange: @escaping (Bool) -> Void = { _ in }) {
        _text = text; self.placeholder = placeholder; self.ink = ink; self.paper = paper; self.font = font
        self.editable = editable; self.onEditingChange = onEditingChange
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let editor = WidgetPlaceholderTextView()
        editor.isRichText = false; editor.importsGraphics = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 3, height: 4)
        editor.delegate = context.coordinator
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - min(selection.location, length)))))
        }
        if let editor = editor as? WidgetPlaceholderTextView { editor.placeholder = placeholder }
        editor.needsDisplay = true
        editor.textColor = ink; editor.insertionPointColor = ink
        editor.drawsBackground = paper.alphaComponent > 0; editor.backgroundColor = paper
        editor.font = font; editor.isEditable = editable; editor.isSelectable = editable
        editor.typingAttributes = [.font: font, .foregroundColor: ink]
        editor.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor, .foregroundColor: NSColor.selectedTextColor]
    }
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WidgetTextEditor
        init(_ parent: WidgetTextEditor) { self.parent = parent }
        public func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            editor.needsDisplay = true
            parent.text = editor.string
        }
        public func textDidBeginEditing(_ notification: Notification) { parent.onEditingChange(true) }
        public func textDidEndEditing(_ notification: Notification) { parent.onEditingChange(false) }
    }
}

/// Draw the hint from the editor's own string, never from a delayed SwiftUI
/// overlay. The placeholder is visual only and never enters the saved note.
final class WidgetPlaceholderTextView: NSTextView {
    var placeholder = ""
    private var editing = false
    var placeholderVisible: Bool { string.isEmpty && !editing && !placeholder.isEmpty }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editing = true; needsDisplay = true }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { editing = false; needsDisplay = true }
        return accepted
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard placeholderVisible else { return }
        let inset = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(x: textContainerOrigin.x + inset, y: textContainerOrigin.y)
        (placeholder as NSString).draw(in: NSRect(origin: origin, size: NSSize(width: max(0, bounds.width - origin.x - inset), height: bounds.height)),
            withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: (textColor ?? .labelColor).withAlphaComponent(0.45)])
    }
}

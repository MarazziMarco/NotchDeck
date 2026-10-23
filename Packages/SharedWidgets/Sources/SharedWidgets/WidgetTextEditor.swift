import AppKit
import SwiftUI

/// Explicit AppKit colors keep text, caret and background legible in transparent windows.
public struct WidgetTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let ink: NSColor
    private let paper: NSColor
    private let font: NSFont
    private let editable: Bool
    private let onEditingChange: (Bool) -> Void
    public init(text: Binding<String>, ink: NSColor = .white, paper: NSColor = .clear,
                font: NSFont = .systemFont(ofSize: 14), editable: Bool = true,
                onEditingChange: @escaping (Bool) -> Void = { _ in }) {
        _text = text; self.ink = ink; self.paper = paper; self.font = font
        self.editable = editable; self.onEditingChange = onEditingChange
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let editor = NSTextView()
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
            parent.text = editor.string
        }
        public func textDidBeginEditing(_ notification: Notification) { parent.onEditingChange(true) }
        public func textDidEndEditing(_ notification: Notification) { parent.onEditingChange(false) }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Private pasteboard type marking a drag that originated inside the File Shelf,
/// so drops back into the shelf are recognised and treated as a safe no-op (not
/// a new external import).
enum ShelfDrag {
    static let typeString = "com.notchdeck.fileshelf.item"
    static let type = NSPasteboard.PasteboardType(typeString)

    /// True when a drop originated inside the File Shelf (so drops back into the
    /// shelf are a safe no-op, not a new external import).
    static func isInternal(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(typeString) }
    }
}

/// Transparent overlay that starts a real AppKit dragging session for one or more
/// shelved files and reports the actual `NSDragOperation` the destination
/// performed. Success is never inferred from the mouse release alone. A drag that
/// stays inside the app resolves to `[]` (no-op) so an accidental drop back into
/// the shelf never mutates anything.
struct FileDragSource: NSViewRepresentable {
    /// URLs to drag (a group when the dragged item is part of a selection).
    let urls: [URL]
    let icon: NSImage
    /// Stable identifiers matching `urls`, carried on the private pasteboard type.
    let identifiers: [String]
    let onComplete: (NSDragOperation) -> Void

    init(url: URL, icon: NSImage, identifier: String = "", onComplete: @escaping (NSDragOperation) -> Void) {
        self.urls = [url]; self.icon = icon; self.identifiers = [identifier]; self.onComplete = onComplete
    }
    init(urls: [URL], icon: NSImage, identifiers: [String], onComplete: @escaping (NSDragOperation) -> Void) {
        self.urls = urls; self.icon = icon; self.identifiers = identifiers; self.onComplete = onComplete
    }

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView(); v.configure(urls: urls, icon: icon, ids: identifiers, onComplete: onComplete); return v
    }
    func updateNSView(_ v: DragSourceView, context: Context) {
        v.configure(urls: urls, icon: icon, ids: identifiers, onComplete: onComplete)
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    private var urls: [URL] = []
    private var icon: NSImage?
    private var ids: [String] = []
    private var onComplete: ((NSDragOperation) -> Void)?

    func configure(urls: [URL], icon: NSImage, ids: [String], onComplete: @escaping (NSDragOperation) -> Void) {
        self.urls = urls; self.icon = icon; self.ids = ids; self.onComplete = onComplete
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty else { return }
        let img = icon ?? NSWorkspace.shared.icon(forFile: urls[0].path)
        var draggingItems: [NSDraggingItem] = []
        for (i, url) in urls.enumerated() {
            // A pasteboard item carrying BOTH the file URL (for external apps) and
            // the private shelf type + stable id (so an internal drop is detected).
            let pbItem = NSPasteboardItem()
            pbItem.setString(url.absoluteString, forType: .fileURL)
            if i < ids.count { pbItem.setString(ids[i], forType: ShelfDrag.type) }
            let di = NSDraggingItem(pasteboardWriter: pbItem)
            let offset = CGFloat(i) * 6
            di.setDraggingFrame(NSRect(x: offset, y: offset, width: 40, height: 40), contents: img)
            draggingItems.append(di)
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.move, .copy]
        // A drop that stays inside NotchDeck (including back into the shelf) does
        // nothing — the file must never disappear on an internal drop.
        case .withinApplication: return []
        @unknown default: return [.move, .copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onComplete?(operation)
    }
}

import XCTest
import SwiftUI
import AppKit
@testable import SharedWidgets

final class EditorContrastTests: XCTestCase {
    @MainActor func testEditorKeepsExplicitInkAndBackgroundInALightWindow() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: WidgetTextEditor(text: .constant("Testo leggibile · nota di prova"), ink: .white,
            paper: NSColor(white: 0.1, alpha: 1)).frame(width: 320, height: 160).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let text = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(text.string, "Testo leggibile · nota di prova")
        XCTAssertEqual(text.textColor, NSColor.white)
        XCTAssertEqual(text.insertionPointColor, NSColor.white)
        XCTAssertTrue(text.drawsBackground)
        XCTAssertEqual(text.backgroundColor, NSColor(white: 0.1, alpha: 1))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/widget-editor-contrast.png"))
    }
    @MainActor func testReversedCardRendersOverNativeEditorAtCompactHeight() throws {
        _ = NSApplication.shared
        let view = WidgetFlipCard(title: "Nota rapida", symbol: "note.text", flipped: .constant(true),
                                  onEdit: {}, onSave: {}) {
            WidgetTextEditor(text: .constant("Questo testo sul fronte deve essere nascosto"), ink: .black)
                .background(Color.yellow)
        } settings: {
            Text("Impostazioni della nota").font(.caption)
        }.frame(width: 340, height: 150)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 340, height: 150)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/widget-reverse-compact.png"))
    }

    @MainActor func testNoteHintDisappearsWhenTypingAndIsNeverSaved() throws {
        _ = NSApplication.shared
        var saved = ""
        let host = NSHostingView(rootView: WidgetTextEditor(text: Binding(get: { saved }, set: { saved = $0 }),
            placeholder: "Scrivi qui la tua nota…").frame(width: 300, height: 120))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 120); host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? WidgetPlaceholderTextView }.first)
        XCTAssertTrue(editor.placeholderVisible)
        XCTAssertEqual(editor.string, "")
        editor.insertText("La mia nota", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertFalse(editor.placeholderVisible)
        XCTAssertEqual(saved, "La mia nota")
        XCTAssertFalse(saved.contains("Scrivi qui"))
    }

    @MainActor func testBackEditorCanBeHitAtItsVisiblePosition() throws {
        _ = NSApplication.shared
        var saved = ""
        let view = WidgetFlipCard(title: "Nota", symbol: "note.text", flipped: .constant(true), onEdit: {}, onSave: {}) {
            Text("Fronte")
        } settings: {
            WidgetTextEditor(text: Binding(get: { saved }, set: { saved = $0 })).frame(height: 120)
        }.frame(width: 340, height: 300)
        let host = NSHostingView(rootView: view)
        let bounds = NSRect(x: 0, y: 0, width: 340, height: 300)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.frame = bounds; host.layoutSubtreeIfNeeded()
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        let point = editor.convert(NSPoint(x: 15, y: 12), to: nil)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        NSApp.postEvent(up, atStart: true)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        window.sendEvent(down)
        XCTAssertTrue(window.firstResponder === editor, "A click on the visible editor did not focus it")
        editor.insertText("Modificabile dal retro", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(saved, "Modificabile dal retro")
    }

}

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

}

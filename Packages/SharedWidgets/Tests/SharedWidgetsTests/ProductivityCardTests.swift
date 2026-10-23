import AppKit
import SwiftUI
@testable import SharedWidgets
import XCTest

final class ProductivityCardTests: XCTestCase {
    @MainActor func testCardFrontsAndSettingsRenderAtBothSizes() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: "/private/tmp/ProductivityPreview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        try library.habits.update { $0.configure([HabitDefinition(title: "Leggere", symbol: "book"), HabitDefinition(title: "Bere acqua", symbol: "drop.fill", target: 8)], title: "La mia routine", showCompleted: true) }
        let original = directory.appendingPathComponent("Appunti.txt")
        try Data("File di prova".utf8).write(to: original)
        try library.shelf.update { $0.add(SharedShelfItem(reference: original)) }
        try library.countdown.update { $0.title = "Il prossimo viaggio"; $0.symbol = "airplane" }
        var windows: [NSWindow] = []
        for kind in ProductivityWidgetKind.allCases {
            for (name,w,h) in [("small",280.0,260.0),("medium",430.0,260.0)] {
                let host = NSHostingView(rootView: SharedProductivityWidget(kind: kind, library: library).frame(width: w,height: h).padding(16).background(Color.gray))
                let bounds = NSRect(x: 0,y: 0,width:w+32,height:h+32)
                let window = NSWindow(contentRect: bounds, styleMask: [.borderless],backing:.buffered,defer:false)
                window.contentView=host;host.frame=bounds;windows.append(window)
                host.layoutSubtreeIfNeeded();RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                try render(host,name:"\(kind.rawValue)-\(name)-front")
                let back: AnyView
                switch kind {
                case .shelf: back = AnyView(SharedShelfCard(library: library, isEditing: false, initiallyFlipped: true))
                case .focus: back = AnyView(SharedFocusCard(library: library, isEditing: false, initiallyFlipped: true))
                case .music: back = AnyView(SharedMusicCard(library: library, isEditing: false, initiallyFlipped: true))
                case .countdown: back = AnyView(SharedCountdownCard(library: library, isEditing: false, initiallyFlipped: true))
                case .habits: back = AnyView(SharedHabitsCard(library: library, isEditing: false, initiallyFlipped: true))
                }
                let backHost = NSHostingView(rootView: back.frame(width: w,height: h).padding(16).background(Color.gray))
                window.contentView = backHost; backHost.frame = bounds;backHost.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                try render(backHost,name:"\(kind.rawValue)-\(name)-back")
            }
        }
    }
    @MainActor func render(_ host: NSView,name:String) throws {
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {fatalError("bitmap")}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/productivity-\(name).png"))
        print("Rendered \(name)")
    }
}

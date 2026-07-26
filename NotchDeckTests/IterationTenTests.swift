import XCTest
@testable import NotchDeck

final class EditorialHomeLayoutTests: XCTestCase {
    private let order = EditorialHomeLayout.defaultOrder
    private func regular(_ w: CGFloat = 760, _ h: CGFloat = 268) -> EditorialPage {
        EditorialHomeLayout.layout(order: order, contentSize: CGSize(width: w, height: h),
                                   layoutClass: .regular, page: 0)
    }

    func testDefaultOrder() {
        XCTAssertEqual(order, ["quickNote", "nowPlaying", "fileShelf", "mirror"])
    }

    func testMirrorIsRightmost() {
        let page = regular()
        XCTAssertEqual(page.zones.last?.moduleID, "mirror")
        let maxX = page.zones.map(\.frame.maxX).max()!
        XCTAssertEqual(page.zones.first { $0.moduleID == "mirror" }!.frame.maxX, maxX, accuracy: 0.5)
    }

    func testSingleRowRegular() {
        let page = regular()
        XCTAssertEqual(page.pageCount, 1)
        XCTAssertTrue(page.zones.allSatisfy { $0.frame.minY == 0 })    // one row
    }

    func testFileShelfFullHeight() {
        let page = regular(760, 268)
        let shelf = page.zones.first { $0.moduleID == "fileShelf" }!
        XCTAssertEqual(shelf.frame.height, 268, accuracy: 0.5)         // full content height
    }

    func testQuickNoteNearSquare() {
        let page = regular(760, 268)
        let note = page.zones.first { $0.moduleID == "quickNote" }!
        let ratio = note.frame.width / note.frame.height
        XCTAssertTrue((0.80...1.30).contains(ratio), "note ratio \(ratio)")
    }

    func testNowPlayingIsPortrait() {
        let page = regular()
        let np = page.zones.first { $0.moduleID == "nowPlaying" }!
        XCTAssertGreaterThan(np.frame.height, np.frame.width)          // vertical widget
    }

    func testNoOverlapNoOverflow() {
        let page = regular(760, 268)
        // Sorted by x; each starts after the previous ends.
        let sorted = page.zones.sorted { $0.frame.minX < $1.frame.minX }
        for i in 1..<sorted.count {
            XCTAssertGreaterThanOrEqual(sorted[i].frame.minX, sorted[i-1].frame.maxX - 0.5)
        }
        XCTAssertLessThanOrEqual(page.zones.map(\.frame.maxX).max()!, 760 + 0.5)
    }

    func testUsesAtLeast85PercentHeight() {
        let h: CGFloat = 268
        let page = regular(760, h)
        let maxH = page.zones.map(\.frame.height).max()!
        XCTAssertGreaterThanOrEqual(maxH / h, 0.85)                    // no blank lower half
    }

    func testCompactTwoPages() {
        let p0 = EditorialHomeLayout.layout(order: order, contentSize: CGSize(width: 620, height: 250),
                                            layoutClass: .compact, page: 0)
        XCTAssertEqual(p0.pageCount, 2)
        XCTAssertEqual(p0.zones.map(\.moduleID), ["quickNote", "nowPlaying"])
        let p1 = EditorialHomeLayout.layout(order: order, contentSize: CGSize(width: 620, height: 250),
                                            layoutClass: .compact, page: 1)
        XCTAssertEqual(p1.zones.map(\.moduleID), ["fileShelf", "mirror"])
    }

    func testMinWidthEnforced() {
        // Very narrow content still keeps mirror at least its minimum.
        let page = EditorialHomeLayout.layout(order: order, contentSize: CGSize(width: 700, height: 260),
                                              layoutClass: .regular, page: 0)
        let mirror = page.zones.first { $0.moduleID == "mirror" }!
        XCTAssertGreaterThanOrEqual(mirror.frame.width, EditorialHomeLayout.minWidths["mirror"]! - 0.5)
    }

    func testPerTabAdaptiveHeights() {
        XCTAssertNotEqual(EditorialHomeLayout.contentHeight(tab: "home", layoutClass: .regular),
                          EditorialHomeLayout.contentHeight(tab: "focus", layoutClass: .regular))
    }
}

@MainActor
final class EditorialSettingsTests: XCTestCase {
    func testDividerDefaultOnAndPersists() {
        XCTAssertTrue(AppSettings().showHomeDividers)
        let s = SettingsStore.inMemory()
        s.settings.showHomeDividers = false
        s.saveNow()
        XCTAssertFalse(s.settings.showHomeDividers)
    }

    func testMirrorCropDefaultCloseAndPersists() {
        XCTAssertEqual(AppSettings().mirrorCropLevel, .close)
        let s = SettingsStore.inMemory()
        s.settings.mirrorCropLevel = .closer
        s.saveNow()
        XCTAssertEqual(s.settings.mirrorCropLevel, .closer)
    }

    func testCompositionDefaultsEditorial() {
        let s = SettingsStore.inMemory()
        let style = s.settings.homeCompositionByClass["regular"] ?? .editorial
        XCTAssertEqual(style, .editorial)
    }

    func testCustomGridLayoutNotOverwrittenByEditorial() {
        let settings = SettingsStore.inMemory()
        let registry = ModuleRegistry(modules: [ClipboardModule(), MirrorModule(), QuickNoteModule()],
                                      settings: settings)
        let dashboard = DashboardModel(settings: settings, registry: registry)
        // User switches this class to grid and customizes.
        settings.settings.homeCompositionByClass["regular"] = .grid
        dashboard.applyPreset(.minimal, for: .regular)
        XCTAssertTrue(dashboard.hasCustomPlacements(for: .regular))
        // Editorial "restore" only touches editorial fields — grid stays.
        settings.settings.editorialOrder = nil
        settings.settings.editorialHidden = []
        XCTAssertTrue(dashboard.hasCustomPlacements(for: .regular))
        XCTAssertEqual(settings.settings.homeCompositionByClass["regular"], .grid)
    }
}

import XCTest
@testable import NotchDeck

final class FilesEditorialLayoutTests: XCTestCase {
    private func regular(_ w: CGFloat = 780, _ h: CGFloat = 300,
                         _ split: FilesRightSplit = .balanced) -> FilesLayout {
        FilesEditorialLayout.layout(contentSize: CGSize(width: w, height: h),
                                    layoutClass: .regular, split: split)
    }

    func testClipboardLeftDownloadsTopRightScreenBottomRight() {
        let f = regular()
        let clip = f.frame("clipboard")!, dl = f.frame("downloads")!, sc = f.frame("screenshot")!
        XCTAssertEqual(clip.minX, 0, accuracy: 0.5)              // clipboard leftmost
        XCTAssertGreaterThan(dl.minX, clip.maxX - 0.5)          // downloads right of clipboard
        XCTAssertEqual(sc.minX, dl.minX, accuracy: 0.5)         // same right column
        XCTAssertGreaterThan(sc.minY, dl.minY)                  // screen below downloads
        XCTAssertEqual(clip.height, 300, accuracy: 0.5)         // clipboard full height
    }

    func testClipboardIsLargestRegion() {
        let f = regular()
        let clipArea = f.frame("clipboard")!.width * f.frame("clipboard")!.height
        let dlArea = f.frame("downloads")!.width * f.frame("downloads")!.height
        let scArea = f.frame("screenshot")!.width * f.frame("screenshot")!.height
        XCTAssertGreaterThan(clipArea, dlArea)
        XCTAssertGreaterThan(clipArea, scArea)
    }

    func testLeftWidthWithinTargetRange() {
        let f = regular(780, 300)
        let available: CGFloat = 780 - 12 - 1
        let ratio = f.frame("clipboard")!.width / available
        XCTAssertTrue((0.56...0.62).contains(ratio), "left ratio \(ratio)")
    }

    func testRightSplitProportionsWithinBounds() {
        for split in FilesRightSplit.allCases {
            let f = regular(780, 300, split)
            let dl = f.frame("downloads")!.height, sc = f.frame("screenshot")!.height
            let frac = dl / (dl + sc)
            XCTAssertTrue((0.42...0.64).contains(frac), "\(split) frac \(frac)")
        }
    }

    func testDownloadsProminentGivesMoreTop() {
        let balanced = regular(780, 300, .balanced).frame("downloads")!.height
        let prominent = regular(780, 300, .downloadsProminent).frame("downloads")!.height
        XCTAssertGreaterThan(prominent, balanced)
    }

    func testCompactTwoPagesNoOverflow() {
        let size = CGSize(width: 620, height: 250)
        let p0 = FilesEditorialLayout.layout(contentSize: size, layoutClass: .compact, split: .balanced, page: 0)
        XCTAssertEqual(p0.pageCount, 2)
        XCTAssertNotNil(p0.frame("clipboard"))
        XCTAssertLessThanOrEqual(p0.frame("clipboard")!.maxX, 620.5)
        let p1 = FilesEditorialLayout.layout(contentSize: size, layoutClass: .compact, split: .balanced, page: 1)
        XCTAssertNotNil(p1.frame("downloads"))
        XCTAssertNotNil(p1.frame("screenshot"))
        XCTAssertLessThanOrEqual(p1.frame("screenshot")!.maxY, 250.5)   // no bottom overflow
    }

    func testScreenRegionHasUsableSpace() {
        let sc = regular().frame("screenshot")!
        XCTAssertGreaterThan(sc.width, 120)     // room for the "Scatta" button
        XCTAssertGreaterThan(sc.height, 60)
    }
}

@MainActor
final class FilesGroupingTests: XCTestCase {
    private func makeRegistry() -> ModuleRegistry {
        let settings = SettingsStore.inMemory()
        return ModuleRegistry(modules: [ClipboardModule(), DownloadsModule(), ScreenshotModule(),
                                        BatteryModule(), PomodoroModule()], settings: settings)
    }

    func testBatteriesNotInDefaultFiles() {
        let registry = makeRegistry()
        XCTAssertEqual(BatteryModule().defaultGroup, .more)
        let ids = Set(registry.modules(in: .files).map(\.id))
        XCTAssertFalse(ids.contains("battery"))
        XCTAssertEqual(ids, ["clipboard", "downloads", "screenshot"])
        XCTAssertTrue(registry.modules(in: .more).contains { $0.id == "battery" })
    }

    func testFocusModeAvailableForFilesModules() {
        let state = AppState(settings: SettingsStore.inMemory())
        for id in ["clipboard", "downloads", "screenshot"] {
            state.focusModule(id)
            XCTAssertEqual(state.focusedModuleID, id)
            state.clearFocus()
        }
    }

    func testFilesCompositionDefaultsEditorial() {
        let s = SettingsStore.inMemory()
        XCTAssertEqual(s.settings.filesCompositionByClass["regular"] ?? .editorial, .editorial)
        XCTAssertEqual(s.settings.filesRightSplit, .balanced)
        XCTAssertEqual(s.settings.clipboardPreviewCount, 3)
    }
}

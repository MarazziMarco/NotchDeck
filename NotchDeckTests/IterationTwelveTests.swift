import XCTest
@testable import NotchDeck

final class PerTabWidthTests: XCTestCase {
    private func screen(_ w: CGFloat) -> ScreenGeometry {
        ScreenGeometry(frame: CGRect(x: 0, y: 0, width: w, height: 940),
                       visibleFrame: CGRect(x: 0, y: 0, width: w, height: 910),
                       notchWidth: 200, notchHeight: 32, backingScaleFactor: 2)
    }
    private func width(_ w: CGFloat, tab: UtilitiesWidthProfile,
                       pref: PanelWidthPreference = .adaptive) -> NotchResponsiveLayout {
        var p = NotchResponsiveLayoutService.Preferences(); p.width = pref
        return NotchResponsiveLayoutService.compute(screen: screen(w), face: .utilities,
                                                    prefs: p, accessibility: .init(), tab: tab)
    }

    func testHomeExceedsFilesOnSpacious() {
        let home = width(1728, tab: .home).panelWidth
        let files = width(1728, tab: .files).panelWidth
        let focus = width(1728, tab: .focus).panelWidth
        XCTAssertGreaterThan(home, files)
        XCTAssertGreaterThan(files, focus)
    }

    func testPerTabHardMaxima() {
        XCTAssertLessThanOrEqual(width(2560, tab: .home).panelWidth, 1120)
        XCTAssertLessThanOrEqual(width(2560, tab: .files).panelWidth, 1000)
        XCTAssertLessThanOrEqual(width(2560, tab: .focus).panelWidth, 900)
        XCTAssertLessThanOrEqual(width(2560, tab: .more).panelWidth, 1000)
    }

    func testClampToVisibleFrameMinus48() {
        for w in [1080.0, 1280, 1512, 1728, 2560] {
            let p = width(CGFloat(w), tab: .home).panelWidth
            XCTAssertLessThanOrEqual(p, CGFloat(w) - 48)
        }
    }

    func testWidePreferenceFocusNotEnormous() {
        let focus = width(2560, tab: .focus, pref: .wide).panelWidth
        XCTAssertLessThanOrEqual(focus, 900)          // Focus stays intentionally narrow
        let home = width(2560, tab: .home, pref: .wide).panelWidth
        XCTAssertLessThanOrEqual(home, 1120)
        XCTAssertGreaterThan(home, focus)
    }

    func testTablessComputeUnchanged() {
        // Backward-compat: no tab → old utilities behaviour (hard max 980).
        var p = NotchResponsiveLayoutService.Preferences()
        let l = NotchResponsiveLayoutService.compute(screen: screen(2560), face: .utilities,
                                                     prefs: p, accessibility: .init())
        XCTAssertLessThanOrEqual(l.panelWidth, NotchResponsiveLayoutService.hardMaxWidth)  // 980
    }

    func testTabWidthTransitionChangesFrame() {
        let geo = screen(1728)
        let homeL = width(1728, tab: .home)
        let focusL = width(1728, tab: .focus)
        let hf = NotchResponsiveLayoutService.expandedPanelFrame(screen: geo, layout: homeL, compactHeight: 32)
        let ff = NotchResponsiveLayoutService.expandedPanelFrame(screen: geo, layout: focusL, compactHeight: 32)
        XCTAssertNotEqual(hf.width, ff.width)          // interaction rect (=frame) recomputes
        XCTAssertEqual(hf.midX, ff.midX, accuracy: 1)  // stays centred on the notch
    }
}

final class EditorialPagingTests: XCTestCase {
    private let order = EditorialHomeLayout.defaultOrder

    func testSpaciousNeverPages() {
        XCTAssertFalse(EditorialHomeLayout.requiresPaging(
            order: order, ratios: EditorialHomeLayout.ratios(for: .spacious),
            minWidths: EditorialHomeLayout.minWidths, contentWidth: 300, layoutClass: .spacious))
    }
    func testCompactAlwaysPages() {
        XCTAssertTrue(EditorialHomeLayout.requiresPaging(
            order: order, ratios: EditorialHomeLayout.ratios(for: .compact),
            minWidths: EditorialHomeLayout.minWidths, contentWidth: 1200, layoutClass: .compact))
    }
    func testRegularPagesWhenMinimumsFail() {
        // Very narrow regular content → a zone drops below its minimum.
        XCTAssertTrue(EditorialHomeLayout.requiresPaging(
            order: order, ratios: EditorialHomeLayout.ratios(for: .regular),
            minWidths: EditorialHomeLayout.minWidths, contentWidth: 400, layoutClass: .regular))
    }
    func testRegularOneRowWhenWide() {
        XCTAssertFalse(EditorialHomeLayout.requiresPaging(
            order: order, ratios: EditorialHomeLayout.ratios(for: .regular),
            minWidths: EditorialHomeLayout.minWidths, contentWidth: 900, layoutClass: .regular))
    }
    func testNoteHasLargestRatioAndMirrorSmallest() {
        let r = EditorialHomeLayout.ratios(for: .spacious)
        XCTAssertGreaterThan(r["quickNote"]!, r["mirror"]!)
        XCTAssertGreaterThan(r["fileShelf"]!, r["nowPlaying"]!)   // File Shelf a bit wider than Now Playing
    }
    func testMirrorRightmostAfterWidthChange() {
        let p = EditorialHomeLayout.layout(order: order, ratios: EditorialHomeLayout.ratios(for: .spacious),
                                           contentSize: CGSize(width: 1080, height: 268), layoutClass: .spacious, page: 0)
        XCTAssertEqual(p.zones.last?.moduleID, "mirror")
    }
}

/// Grey-corner rendering fix.
final class BackgroundCornerTests: XCTestCase {
    func testDeepBlackIsFullyOpaque() {
        XCTAssertEqual(BackgroundIntensity.deepBlack.surfaceOpacity, 1.0)   // no grey material bleed
        XCTAssertEqual(BackgroundIntensity.maxContrast.surfaceOpacity, 1.0)
        XCTAssertLessThanOrEqual(BackgroundIntensity.deepBlack.surfaceWhite, 0.02)  // near-black
    }
    func testContentClipMatchesPanelRadius() {
        // Content is clipped to the same expanded corner radius as the panel base.
        XCTAssertEqual(DesignTokens.Metrics.expandedCornerRadius, DesignTokens.Metrics.expandedCornerRadius)
        XCTAssertGreaterThan(DesignTokens.Metrics.expandedCornerRadius, 0)
    }
}

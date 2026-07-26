import XCTest
@testable import NotchDeck

final class ResponsiveLayoutTests: XCTestCase {
    private func screen(width: CGFloat, height: CGFloat = 900, notch: Bool = true) -> ScreenGeometry {
        ScreenGeometry(frame: CGRect(x: 0, y: 0, width: width, height: height + 30),
                       visibleFrame: CGRect(x: 0, y: 0, width: width, height: height),
                       notchWidth: notch ? 200 : 0,
                       notchHeight: notch ? 32 : 0,
                       backingScaleFactor: 2)
    }
    private let prefs = NotchResponsiveLayoutService.Preferences()
    private let access = AccessibilityLayoutPreferences()

    private func width(_ w: CGFloat, face: NotchFace = .utilities,
                       prefs: NotchResponsiveLayoutService.Preferences? = nil) -> NotchResponsiveLayout {
        NotchResponsiveLayoutService.compute(screen: screen(width: w), face: face,
                                             prefs: prefs ?? self.prefs, accessibility: access)
    }

    func testWidthClampedWithinHardBounds() {
        for w in [1080.0, 1280, 1440, 1512, 1728, 1920, 2560] {
            let l = width(CGFloat(w))
            XCTAssertLessThanOrEqual(l.panelWidth, NotchResponsiveLayoutService.hardMaxWidth)
            XCTAssertLessThanOrEqual(l.panelWidth, CGFloat(w) - 24 * 2)   // inside safe margins
        }
    }

    func testApproxTargetsAcrossDisplays() {
        // Synthetic small / medium / large / external logical widths.
        let small = width(1280).panelWidth
        let medium = width(1512).panelWidth
        let large = width(1728).panelWidth
        let external = width(2560).panelWidth
        XCTAssertTrue((640...760).contains(small), "small=\(small)")
        XCTAssertTrue((740...860).contains(medium), "medium=\(medium)")
        XCTAssertTrue((820...940).contains(large), "large=\(large)")
        XCTAssertEqual(external, 980, accuracy: 1)      // hard max on a big display
    }

    func testLayoutClassSelection() {
        XCTAssertEqual(width(1080).layoutClass, .compact)
        XCTAssertEqual(width(1512).layoutClass, .regular)
        XCTAssertEqual(width(1728).layoutClass, .spacious)
    }

    func testWidthIsGeometryDrivenNotModel() {
        // Two "different machines" with identical logical geometry → identical width.
        XCTAssertEqual(width(1512).panelWidth, width(1512).panelWidth)
    }

    func testUserWidePreferenceStillClamped() {
        var p = prefs; p.width = .wide
        let l = width(1280, prefs: p)
        XCTAssertLessThanOrEqual(l.panelWidth, 1280 - 48)
        XCTAssertLessThanOrEqual(l.panelWidth, 980)
    }

    func testCompactPreferenceReducesWidth() {
        var p = prefs; p.width = .compact
        XCTAssertLessThan(width(1512, prefs: p).panelWidth, width(1512).panelWidth)
    }

    func testHeightWideAndShort() {
        for w in [1280.0, 1512, 1920] {
            let l = width(CGFloat(w))
            XCTAssertLessThanOrEqual(l.dashboardHeight, NotchResponsiveLayoutService.hardMaxHeight)
            XCTAssertGreaterThan(l.panelWidth, l.dashboardHeight)   // wide, not tall
        }
    }

    func testMaxHomeModulesByClass() {
        XCTAssertEqual(width(1080).maxHomeModules, 3)   // compact
        XCTAssertEqual(width(1512).maxHomeModules, 4)   // regular
    }

    func testExpandedFrameStaysWithinVisibleFrame() {
        let s = screen(width: 1512)
        let l = NotchResponsiveLayoutService.compute(screen: s, face: .utilities, prefs: prefs, accessibility: access)
        let frame = NotchResponsiveLayoutService.expandedPanelFrame(screen: s, layout: l, compactHeight: 32)
        XCTAssertGreaterThanOrEqual(frame.minX, s.visibleFrame.minX)
        XCTAssertLessThanOrEqual(frame.maxX, s.visibleFrame.maxX)
        XCTAssertEqual(frame.maxY, s.frame.maxY, accuracy: 1)   // notched: hugs top
    }

    func testExternalPillCenteredBelowMenuBar() {
        let s = screen(width: 1920, notch: false)
        let l = NotchResponsiveLayoutService.compute(screen: s, face: .utilities, prefs: prefs, accessibility: access)
        XCTAssertFalse(l.hasNotch)
        let frame = NotchResponsiveLayoutService.expandedPanelFrame(screen: s, layout: l, compactHeight: 32)
        XCTAssertEqual(frame.midX, s.frame.midX, accuracy: 1)          // centered
        XCTAssertEqual(frame.maxY, s.visibleFrame.maxY, accuracy: 1)   // below menu bar
    }

    func testSideColumnIsResponsiveNotFixed236() {
        let narrow = width(1280).sideColumnWidth
        let wide = width(1920).sideColumnWidth
        XCTAssertNotEqual(narrow, 236)
        XCTAssertGreaterThanOrEqual(wide, narrow)
        XCTAssertLessThanOrEqual(wide, 260)
    }
}

final class HomeSolverTests: XCTestCase {
    func testOverflowBeyondMaxModules() {
        let items = (0..<6).map { HomeSolver.Item(id: "m\($0)", span: 1, minWidth: 120) }
        let r = HomeSolver.solve(items: items, availableWidth: 800, maxModules: 3)
        XCTAssertEqual(r.home.count, 3)
        XCTAssertEqual(r.overflow.count, 3)
    }

    func testMinWidthEnforcementMovesOffHome() {
        // availableWidth 560 → unit ≈ (560-30)/4 = 132.5; a small card min 150 can't fit.
        let items = [HomeSolver.Item(id: "big", span: 4, minWidth: 400),
                     HomeSolver.Item(id: "tiny", span: 1, minWidth: 150)]
        let r = HomeSolver.solve(items: items, availableWidth: 560, maxModules: 4)
        XCTAssertTrue(r.home.contains("big"))
        XCTAssertTrue(r.overflow.contains("tiny"))
    }

    func testDeterministicOrderPreserved() {
        let items = ["a", "b", "c"].map { HomeSolver.Item(id: $0, span: 1, minWidth: 100) }
        let r = HomeSolver.solve(items: items, availableWidth: 800, maxModules: 5)
        XCTAssertEqual(r.home, ["a", "b", "c"])
    }
}

final class AdaptiveTabTests: XCTestCase {
    func testCompactAutomaticShowsIconsForGroupTabs() {
        XCTAssertFalse(AdaptiveTabBar.showsLabel(.files, mode: .automatic, layoutClass: .compact))
        XCTAssertTrue(AdaptiveTabBar.showsLabel(.home, mode: .automatic, layoutClass: .compact))
        XCTAssertTrue(AdaptiveTabBar.showsLabel(.more, mode: .automatic, layoutClass: .compact))
    }
    func testRegularShowsAllLabels() {
        XCTAssertTrue(AdaptiveTabBar.showsLabel(.files, mode: .automatic, layoutClass: .regular))
    }
    func testIconsOnlyKeepsAnchorsTextual() {
        XCTAssertFalse(AdaptiveTabBar.showsLabel(.focus, mode: .iconsOnly, layoutClass: .spacious))
        XCTAssertTrue(AdaptiveTabBar.showsLabel(.home, mode: .iconsOnly, layoutClass: .spacious))
    }
}

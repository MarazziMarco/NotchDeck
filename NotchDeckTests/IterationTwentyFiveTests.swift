import XCTest
@testable import NotchDeck

/// Compact Focus timer refinement: shorter capsule, rounded corners,
/// content-driven asymmetric wings, smaller ring/text. Physical idle, expanded,
/// and other activities are unaffected.
final class CompactFocusGeometryTests: XCTestCase {
    private let notchW: CGFloat = 200
    private let notchH: CGFloat = 38
    private func metrics(notch: Bool = true) -> DisplayMetrics {
        DisplayMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       notchHeight: notch ? notchH : 0, notchWidth: notch ? notchW : 0,
                       backingScaleFactor: 2)
    }
    private var wings: (left: CGFloat, right: CGFloat) {
        (CompactFocusGeometry.leftWingWidth, CompactFocusGeometry.rightWingWidth)
    }

    // MARK: Height & radius

    func testHeightInTargetRange() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.visualHeight, 38)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.visualHeight, 40)
    }
    func testShorterThanPreviousCapsule() {
        XCTAssertLessThan(CompactFocusGeometry.visualHeight, DesignTokens.Metrics.compactVisualHeight) // < 44
    }
    func testCornerRadiusRounded() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.cornerRadius, 16)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.cornerRadius, 18)
        // ≈ half the height → clearly rounded lower corners, not square.
        XCTAssertLessThanOrEqual(abs(CompactFocusGeometry.cornerRadius - CompactFocusGeometry.visualHeight / 2), 4)
    }

    // MARK: Content-driven asymmetric wings

    func testLeadingOuterPaddingSmall() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.leadingOuterPadding, 8)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.leadingOuterPadding, 10)
    }
    func testLeftWingIsContentHugging() {
        // left = pad + icon + notch-safe (NOT the old ~105pt).
        XCTAssertEqual(CompactFocusGeometry.leftWingWidth,
                       9 + CompactFocusGeometry.timerDiameter + CompactFocusGeometry.notchSafeInset, accuracy: 0.5)
        XCTAssertLessThan(CompactFocusGeometry.leftWingWidth, 60)
        XCTAssertLessThan(CompactFocusGeometry.leftWingWidth, 105)   // no oversized fixed wing
    }
    func testRightWingBasedOnMeasuredText() {
        XCTAssertEqual(CompactFocusGeometry.rightWingWidth,
                       CompactFocusGeometry.notchSafeInset + CompactFocusGeometry.timeTextWidth
                       + CompactFocusGeometry.trailingOuterPadding, accuracy: 0.5)
    }
    func testWingsAreAsymmetric() {
        // Text wing is wider than the icon wing — no empty width for symmetry.
        XCTAssertGreaterThan(CompactFocusGeometry.rightWingWidth, CompactFocusGeometry.leftWingWidth)
    }
    func testIconNearOuterLeftEdge() {
        // Icon left edge = leadingOuterPadding from the capsule's outer-left edge.
        XCTAssertEqual(CompactFocusGeometry.leadingOuterPadding, 9, accuracy: 1)
    }

    // MARK: Icon & text sizing

    func testTimerDiameterReduced() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.timerDiameter, 21)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.timerDiameter, 22)
        XCTAssertLessThan(CompactFocusGeometry.timerDiameter, 24)          // smaller than before
        XCTAssertGreaterThan(CompactFocusGeometry.timerDiameter, 15)       // not the tiny original
    }
    func testStrokeAndGlyph() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.timerStroke, 2.4)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.timerStroke, 2.6)
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.timerGlyphSize, 11)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.timerGlyphSize, 12)
    }
    func testTimeFontReduced() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.timeFontSize, 19)
        XCTAssertLessThanOrEqual(CompactFocusGeometry.timeFontSize, 20)
        XCTAssertEqual(CompactTimerLayout.timeTextSize, CompactFocusGeometry.timeFontSize)
    }
    func testTimeTextWidthFitsFiveChars() {
        XCTAssertGreaterThanOrEqual(CompactFocusGeometry.timeTextWidth, 55)   // "00:00" @20pt mono
        for v in ["25:00", "22:41", "05:12", "00:09"] { XCTAssertEqual(v.count, 5) }
    }

    // MARK: Panel layout — asymmetric, notch-aligned, unchanged elsewhere

    func testFocusPanelUsesContentWidthAndReducedHeight() {
        let l = NotchGeometryService.layout(
            for: metrics(), state: .compact, face: .utilities, expandedContentHeight: 300,
            compactExtraWidth: CompactFocusGeometry.totalExtraWidth,
            compactActivity: true, compactWings: wings,
            compactActivityHeight: CompactFocusGeometry.visualHeight)
        XCTAssertEqual(l.panelFrame.height, CompactFocusGeometry.visualHeight, accuracy: 0.5)
        XCTAssertEqual(l.panelFrame.width, wings.left + notchW + wings.right, accuracy: 0.5)
    }
    func testFocusPanelNotchCentred() {
        // The notch region (not the panel centre) aligns with the screen centre.
        let m = metrics()
        let l = NotchGeometryService.layout(
            for: m, state: .compact, face: .utilities, expandedContentHeight: 300,
            compactExtraWidth: CompactFocusGeometry.totalExtraWidth,
            compactActivity: true, compactWings: wings,
            compactActivityHeight: CompactFocusGeometry.visualHeight)
        let notchCentreX = l.panelFrame.minX + wings.left + notchW / 2
        XCTAssertEqual(notchCentreX, m.frame.midX, accuracy: 1)
    }
    func testPhysicalIdleUnchanged() {
        let s = NotchGeometryService.physicalIdleSize(for: metrics())
        XCTAssertEqual(s.width, notchW, accuracy: 0.5)
        XCTAssertEqual(s.height, notchH, accuracy: 0.5)
    }
    func testOtherActivityStillFortyFourSymmetric() {
        // Non-Focus activity (no wings) keeps the 44pt symmetric capsule.
        let l = NotchGeometryService.layout(
            for: metrics(), state: .compact, face: .utilities, expandedContentHeight: 300,
            compactExtraWidth: 210, compactActivity: true)
        XCTAssertEqual(l.panelFrame.height, DesignTokens.Metrics.compactVisualHeight, accuracy: 0.5) // 44
    }
    func testExpandedUnchanged() {
        let reserve = NotchGeometryService.compactHeight(for: metrics())
        let l = NotchGeometryService.layout(for: metrics(), state: .expanded, face: .utilities,
                                            expandedContentHeight: 300)
        XCTAssertEqual(l.panelFrame.height, 300 + reserve, accuracy: 0.5)
    }

    // MARK: Focus-timer detection

    func testFocusTimerLayoutDetection() {
        let ring = WingSlot(symbol: "timer", progress: 0.5, tint: .running)
        let time = WingSlot(text: "22:41", tint: .running, monospacedDigits: true, emphasize: true)
        let focus = LiveActivityLayout(leading: ring, trailing: time)
        XCTAssertTrue(focus.isFocusTimer)

        let agents = LiveActivityLayout(leading: WingSlot(symbol: "cpu", text: "2 active", tint: .agentActive))
        XCTAssertFalse(agents.isFocusTimer)
        XCTAssertFalse(LiveActivityLayout.empty.isFocusTimer)
    }
}

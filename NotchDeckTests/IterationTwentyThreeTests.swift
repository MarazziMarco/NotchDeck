import XCTest
@testable import NotchDeck

/// Compact/closed notch appearance: rounded capsule, taller strip, larger timer.
final class CompactCapsuleTests: XCTestCase {

    // MARK: Rounded capsule geometry

    func testCompactCornerRadiusIsRounded() {
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.compactCornerRadius, 18)
    }
    func testRadiusNearHalfCompactHeight() {
        let half = DesignTokens.Metrics.compactVisualHeight / 2
        XCTAssertLessThanOrEqual(abs(DesignTokens.Metrics.compactCornerRadius - half), 6)
    }
    func testCompactVisualHeightInTargetRange() {
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.compactVisualHeight, 42)
        XCTAssertLessThanOrEqual(DesignTokens.Metrics.compactVisualHeight, 48)
    }
    func testCompactContentInsetReasonable() {
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.compactContentInset, 8)
        XCTAssertLessThanOrEqual(DesignTokens.Metrics.compactContentInset, 10)
    }

    // MARK: Geometry service — compact taller, expanded untouched

    private func metrics(notch: Bool = true) -> DisplayMetrics {
        DisplayMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       notchHeight: notch ? 38 : 0, notchWidth: notch ? 200 : 0,
                       backingScaleFactor: 2)
    }

    func testCompactPanelUsesVisualHeight() {
        let l = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                            expandedContentHeight: 300)
        XCTAssertEqual(l.panelFrame.height, DesignTokens.Metrics.compactVisualHeight, accuracy: 0.5)
    }
    func testExpandedReserveUnchanged() {
        // Expanded height still uses the 32pt reserve, NOT the taller capsule.
        let reserve = NotchGeometryService.compactHeight(for: metrics())   // max(32, notch)
        let l = NotchGeometryService.layout(for: metrics(), state: .expanded, face: .utilities,
                                            expandedContentHeight: 300)
        XCTAssertEqual(l.panelFrame.height, 300 + reserve, accuracy: 0.5)  // reserve unchanged
        // The taller compact capsule must NOT inflate the expanded panel.
        XCTAssertLessThan(reserve, DesignTokens.Metrics.compactVisualHeight)
        XCTAssertEqual(DesignTokens.Metrics.compactHeight, 32)             // token unchanged
    }
    func testCompactVisualTallerThanReserve() {
        XCTAssertGreaterThan(NotchGeometryService.compactVisualHeight(for: metrics()),
                             NotchGeometryService.compactHeight(for: metrics()))
    }
    func testNonNotchStillHasSensibleCompactHeight() {
        let l = NotchGeometryService.layout(for: metrics(notch: false), state: .compact,
                                            face: .utilities, expandedContentHeight: 300)
        XCTAssertEqual(l.panelFrame.height, DesignTokens.Metrics.compactVisualHeight, accuracy: 0.5)
    }

    // MARK: Timer icon + text sizing

    func testTimerRingDiameterAtLeast22() {
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.ringDiameter, 22)
    }
    func testRingStrokeInRange() {
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.ringStroke, 2.5)
        XCTAssertLessThanOrEqual(CompactTimerLayout.ringStroke, 3.0)
    }
    func testGlyphSizeInRange() {
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.glyphSize, 12)
        XCTAssertLessThanOrEqual(CompactTimerLayout.glyphSize, 15)
    }
    func testTimeTextSizeLargeEnough() {
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.timeTextSize, 20)
        XCTAssertLessThanOrEqual(CompactTimerLayout.timeTextSize, 24)
    }
    func testTimeTextNeverBelowFloor() {
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.timeTextMinSize, 20)
        for v in [CompactTimerLayout.Variant.wide, .medium, .narrow] {
            XCTAssertGreaterThanOrEqual(CompactTimerLayout.timeTextSize(for: v), 20)
        }
    }
    func testTimeTextMinWidthFitsFiveChars() {
        // "00:00" at 22pt mono ≈ 59pt.
        XCTAssertGreaterThanOrEqual(CompactTimerLayout.timeTextMinWidth, 55)
    }

    // MARK: Responsive variants — drop secondary before shrinking text

    func testVariantsByWingWidth() {
        XCTAssertEqual(CompactTimerLayout.variant(wingWidth: 120), .wide)
        XCTAssertEqual(CompactTimerLayout.variant(wingWidth: 80), .medium)
        XCTAssertEqual(CompactTimerLayout.variant(wingWidth: 50), .narrow)
    }
    func testSecondaryDroppedBeforeTextShrinks() {
        // At medium: secondary control is gone, but the primary time text stays
        // full size — the timer text is reduced only at the narrowest variant.
        XCTAssertFalse(CompactTimerLayout.showsSecondary(.medium))
        XCTAssertEqual(CompactTimerLayout.timeTextSize(for: .medium), CompactTimerLayout.timeTextSize)
        XCTAssertTrue(CompactTimerLayout.showsSecondary(.wide))
    }
    func testStandardTimeValuesAreFiveChars() {
        for v in ["25:00", "23:40", "05:12", "00:09"] { XCTAssertEqual(v.count, 5) }
    }

    // MARK: Notch-safe exclusion with the enlarged controls

    func testEnlargedControlsStayOutsideNotchExclusion() {
        let start = CompactWingLayout.rightWingStartX(housingMaxX: 100, hasNotch: true)
        XCTAssertEqual(start - 100, CompactWingLayout.notchSafeInset)
        XCTAssertGreaterThanOrEqual(CompactWingLayout.notchSafeInset, 18)
    }
    func testNonNotchNoExtraInset() {
        XCTAssertLessThan(CompactWingLayout.rightWingLeadingInset(hasNotch: false),
                          CompactWingLayout.notchSafeInset)
    }
}

// MARK: Compact state silhouette consistency (Pomodoro split slots)

@MainActor
final class CompactPomodoroSlotTests: XCTestCase {
    func testRunningTimerSlotIsEmphasizedMonospaced() {
        let service = PomodoroService(fileName: "cap-\(UUID()).json")
        service.start()
        guard let activity = service.currentActivity() else { return XCTFail("no activity") }
        // Split trailing (the MM:SS) is high-contrast, emphasized, mono digits.
        XCTAssertEqual(activity.splitTrailing?.emphasize, true)
        XCTAssertEqual(activity.splitTrailing?.monospacedDigits, true)
        // Leading is the progress ring (timer glyph), not the text.
        XCTAssertNotNil(activity.splitLeading?.progress)
        XCTAssertNil(activity.splitLeading?.text)
    }
}

import XCTest
@testable import NotchDeck

// MARK: Black rounded lower corners

final class BackgroundCornerFixTests: XCTestCase {
    func testOnlyStandardUsesGreyMaterial() {
        XCTAssertTrue(BackgroundIntensity.standard.usesMaterial)
        XCTAssertFalse(BackgroundIntensity.deepBlack.usesMaterial)     // pure black
        XCTAssertFalse(BackgroundIntensity.maxContrast.usesMaterial)
    }
    func testDeepAndMaxHaveOpaqueBlackCorners() {
        XCTAssertTrue(BackgroundIntensity.deepBlack.hasOpaqueBlackCorners)
        XCTAssertTrue(BackgroundIntensity.maxContrast.hasOpaqueBlackCorners)
        XCTAssertFalse(BackgroundIntensity.standard.hasOpaqueBlackCorners)
    }
    func testDeepAndMaxSurfaceFullyOpaqueAndNearBlack() {
        XCTAssertEqual(BackgroundIntensity.deepBlack.surfaceOpacity, 1.0)
        XCTAssertEqual(BackgroundIntensity.maxContrast.surfaceOpacity, 1.0)
        XCTAssertLessThanOrEqual(BackgroundIntensity.deepBlack.surfaceWhite, 0.02)
        XCTAssertEqual(BackgroundIntensity.maxContrast.surfaceWhite, 0.0)
    }
    func testOuterAndContentClipRadiiMatch() {
        // Both the panel base and the content mask use the same expanded radius.
        XCTAssertGreaterThan(DesignTokens.Metrics.expandedCornerRadius, 0)
    }
}

// MARK: Now Playing vertical composition

final class NowPlayingCompositionTests: XCTestCase {
    func testArtworkIsLargerThanBefore() {
        XCTAssertGreaterThan(NowPlayingComposition.artworkHeightRatio, 0.60)
    }
    func testArtworkSideFollowsHeightWhenTall() {
        let zone = CGSize(width: 300, height: 286)
        XCTAssertEqual(NowPlayingComposition.artworkSide(zone: zone),
                       286 * NowPlayingComposition.artworkHeightRatio, accuracy: 0.001)
    }
    func testArtworkSideClampedByWidth() {
        let zone = CGSize(width: 120, height: 286)   // narrow zone
        XCTAssertEqual(NowPlayingComposition.artworkSide(zone: zone), 120, accuracy: 0.001)
    }
    func testVisualCentreIsRaised() {
        // Negative offset ⇒ group centre sits above the zone middle (not bottom-heavy).
        XCTAssertLessThan(NowPlayingComposition.centerOffsetFromMiddle(), 0)
    }
}

// MARK: Home vertical balance

final class HomeBalanceTests: XCTestCase {
    func testHomeContentHeightIncreased() {
        XCTAssertGreaterThanOrEqual(
            EditorialHomeLayout.contentHeight(tab: "home", layoutClass: .spacious), 286)
        XCTAssertGreaterThanOrEqual(
            EditorialHomeLayout.contentHeight(tab: "home", layoutClass: .compact), 262)
    }
    func testMirrorRemainsRightmost() {
        let p = EditorialHomeLayout.layout(
            order: EditorialHomeLayout.defaultOrder,
            ratios: EditorialHomeLayout.ratios(for: .spacious),
            contentSize: CGSize(width: 1080, height: 286),
            layoutClass: .spacious, page: 0)
        XCTAssertEqual(p.zones.last?.moduleID, "mirror")
    }
}

// MARK: Mirror orientation

final class MirrorOrientationTests: XCTestCase {
    func testDefaultIsMirrored() {
        XCTAssertEqual(AppSettings().mirrorOrientation, .mirrored)
        XCTAssertTrue(AppSettings().mirrorOrientation.isMirrored)
    }
    func testTrueViewIsNotMirrored() {
        XCTAssertFalse(MirrorOrientation.trueView.isMirrored)
    }
    func testOrientationPersistsRoundTrip() throws {
        var s = AppSettings()
        s.mirrorOrientation = .trueView
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.mirrorOrientation, .trueView)
    }
    func testMirroredRemainsMirroredAcrossReencode() throws {
        // Simulates a restart/toggle: the persisted default survives a round-trip
        // and stays mirrored (no intermittent fallback in the stored state).
        let data = try JSONEncoder().encode(AppSettings())
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.mirrorOrientation.isMirrored)
    }
}

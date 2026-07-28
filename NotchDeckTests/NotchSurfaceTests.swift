import AppKit
import XCTest
@testable import NotchDeck

final class NotchSurfaceDescriptorTests: XCTestCase {
    func testExpandedRenderingUsesOneAuthoritativeOpaqueBackground() {
        for intensity in BackgroundIntensity.allCases {
            let descriptor = NotchSurfaceDescriptor.resolve(
                presentation: .expanded,
                compactFocus: false,
                intensity: intensity
            )
            XCTAssertEqual(descriptor.backgroundLayerCount, 1)
            XCTAssertTrue(descriptor.isOpaque)
            XCTAssertFalse(descriptor.usesMaterial)
        }
    }

    func testCompactRenderingRetainsOneBlackBackground() {
        let descriptor = NotchSurfaceDescriptor.resolve(
            presentation: .compact,
            compactFocus: false,
            intensity: .standard
        )
        XCTAssertEqual(descriptor.backgroundLayerCount, 1)
        XCTAssertEqual(descriptor.surfaceWhite, 0)
        XCTAssertTrue(descriptor.isOpaque)
        XCTAssertFalse(descriptor.usesMaterial)
    }

    func testExpandedSurfaceFillsPanelBoundsWithoutExposingHost() {
        let descriptor = NotchSurfaceDescriptor.resolve(
            presentation: .expanded,
            compactFocus: false,
            intensity: .deepBlack
        )
        XCTAssertEqual(descriptor.outerPadding, 0)
        XCTAssertEqual(descriptor.borderWidth, 0)
    }

    func testCompactAndExpandedUseSharedCornerGeometry() {
        XCTAssertEqual(
            NotchSurfaceGeometry.cornerRadius(
                presentation: .expanded,
                compactFocus: false
            ),
            DesignTokens.Metrics.expandedCornerRadius
        )
        XCTAssertEqual(
            NotchSurfaceGeometry.cornerRadius(
                presentation: .compact,
                compactFocus: false
            ),
            DesignTokens.Metrics.compactCornerRadius
        )
        XCTAssertEqual(
            NotchSurfaceGeometry.cornerRadius(
                presentation: .compact,
                compactFocus: true
            ),
            CompactFocusGeometry.cornerRadius
        )
    }

    func testExpandedShadowConfigurationCannotBecomeASecondPanel() {
        let descriptor = NotchSurfaceDescriptor.resolve(
            presentation: .expanded,
            compactFocus: false,
            intensity: .deepBlack
        )
        XCTAssertEqual(descriptor.shadowRadius, NotchSurfaceGeometry.expandedShadowRadius)
        XCTAssertEqual(descriptor.shadowOpacity, NotchSurfaceGeometry.expandedShadowOpacity)
        XCTAssertEqual(descriptor.shadowOffsetY, NotchSurfaceGeometry.expandedShadowOffsetY)
        XCTAssertEqual(descriptor.shadowRadius, 0)
        XCTAssertEqual(descriptor.shadowOpacity, 0)
        XCTAssertEqual(descriptor.shadowOffsetY, 0)
        XCTAssertEqual(descriptor.borderWidth, 0)
    }

    func testReduceMotionDoesNotChangeFinalSurfaceOwnership() {
        let normal = NotchSurfaceTransitionPolicy.descriptor(
            presentation: .expanded,
            compactFocus: false,
            intensity: .deepBlack,
            reduceMotion: false
        )
        let reduced = NotchSurfaceTransitionPolicy.descriptor(
            presentation: .expanded,
            compactFocus: false,
            intensity: .deepBlack,
            reduceMotion: true
        )
        XCTAssertEqual(normal, reduced)
    }
}

@MainActor
final class NotchPanelTransparencyTests: XCTestCase {
    func testPanelHostIsTransparentAndNonOpaque() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
    }
}

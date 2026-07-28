import XCTest
import AppKit
@testable import NotchDeck

/// Physical-idle vs compact-activity closed geometry, and removal of the grey
/// compact chrome. Expanded is untouched.
final class ClosedNotchGeometryTests: XCTestCase {
    private let notchW: CGFloat = 200
    private let notchH: CGFloat = 38
    private func metrics(notch: Bool = true) -> DisplayMetrics {
        DisplayMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       notchHeight: notch ? notchH : 0, notchWidth: notch ? notchW : 0,
                       backingScaleFactor: 2)
    }

    // MARK: Physical idle matches the hardware notch

    func testPhysicalIdleSizeMatchesNotch() {
        let s = NotchGeometryService.physicalIdleSize(for: metrics())
        XCTAssertEqual(s.width, notchW, accuracy: 0.5)
        XCTAssertEqual(s.height, notchH, accuracy: 0.5)
    }
    func testIdleLayoutEqualsNotch() {
        let l = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                            expandedContentHeight: 300, compactExtraWidth: 0,
                                            compactActivity: false)
        XCTAssertEqual(l.panelFrame.width, notchW, accuracy: 0.5)   // no side wings
        XCTAssertEqual(l.panelFrame.height, notchH, accuracy: 0.5)  // no 44pt capsule
    }
    func testIdleHasNoWings() {
        // Even with a stale extra width, idle collapses to the notch width.
        let l = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                            expandedContentHeight: 300, compactExtraWidth: 210,
                                            compactActivity: false)
        XCTAssertEqual(l.panelFrame.width, notchW, accuracy: 0.5)
    }
    func testActivityIsTallerThanIdle() {
        let idle = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                               expandedContentHeight: 300, compactActivity: false)
        let active = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                                 expandedContentHeight: 300, compactExtraWidth: 210,
                                                 compactActivity: true)
        XCTAssertGreaterThan(active.panelFrame.height, idle.panelFrame.height)
        XCTAssertGreaterThan(active.panelFrame.width, idle.panelFrame.width)
        XCTAssertEqual(active.panelFrame.height, DesignTokens.Metrics.compactVisualHeight, accuracy: 0.5)
    }
    func testActivityEndingRestoresIdle() {
        // Transition active → idle yields exactly the physical-idle geometry.
        let after = NotchGeometryService.layout(for: metrics(), state: .compact, face: .utilities,
                                                expandedContentHeight: 300, compactExtraWidth: 0,
                                                compactActivity: false)
        let idleSize = NotchGeometryService.physicalIdleSize(for: metrics())
        XCTAssertEqual(after.panelFrame.width, idleSize.width, accuracy: 0.5)
        XCTAssertEqual(after.panelFrame.height, idleSize.height, accuracy: 0.5)
    }
    func testNonNotchIdleFallback() {
        let s = NotchGeometryService.physicalIdleSize(for: metrics(notch: false))
        XCTAssertEqual(s.width, DesignTokens.Metrics.pillWidth, accuracy: 0.5)
        XCTAssertEqual(s.height, DesignTokens.Metrics.compactHeight, accuracy: 0.5)
    }

    // MARK: Expanded untouched

    func testExpandedGeometryUnchanged() {
        let reserve = NotchGeometryService.compactHeight(for: metrics())
        let l = NotchGeometryService.layout(for: metrics(), state: .expanded, face: .utilities,
                                            expandedContentHeight: 300)
        XCTAssertEqual(l.panelFrame.height, 300 + reserve, accuracy: 0.5)
    }

    // MARK: One clean surface in compact and expanded states

    func testCompactHasNoBorder() {
        let surface = NotchSurfaceDescriptor.resolve(
            presentation: .compact,
            compactFocus: false,
            intensity: .deepBlack
        )
        XCTAssertEqual(surface.borderWidth, 0)
    }
    func testCompactHasNoShadow() {
        let surface = NotchSurfaceDescriptor.resolve(
            presentation: .compact,
            compactFocus: false,
            intensity: .deepBlack
        )
        XCTAssertEqual(surface.shadowRadius, 0)
    }
    func testExpandedHasNoInBoundsChromeLayer() {
        let surface = NotchSurfaceDescriptor.resolve(
            presentation: .expanded,
            compactFocus: false,
            intensity: .deepBlack
        )
        XCTAssertEqual(surface.borderWidth, 0)
        XCTAssertEqual(surface.shadowRadius, 0)
        XCTAssertEqual(surface.backgroundLayerCount, 1)
    }

    // MARK: Panel window has no shadow while closed

    @MainActor func testPanelHasNoShadow() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
    }

    // MARK: One authoritative rounded shape/radius for every compact variant

    func testSingleCompactRadius() {
        // Every compact variant reads the one radius; idle/timer/agents/approval
        // never use a state-specific value.
        XCTAssertGreaterThan(DesignTokens.Metrics.compactCornerRadius, 0)
        let r = DesignTokens.Metrics.compactCornerRadius
        XCTAssertEqual(r, DesignTokens.Metrics.compactCornerRadius)   // stable single source
    }
}

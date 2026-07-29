import XCTest
import SwiftUI
@testable import NotchDeck

final class NotchGeometryServiceTests: XCTestCase {

    private func notchScreen() -> DisplayMetrics {
        DisplayMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       notchHeight: 32, notchWidth: 200, backingScaleFactor: 2)
    }
    private func plainScreen() -> DisplayMetrics {
        DisplayMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                       notchHeight: 0, notchWidth: 0, backingScaleFactor: 1)
    }

    func testCompactCentersHorizontally() {
        let m = notchScreen()
        let layout = NotchGeometryService.layout(for: m, state: .compact, face: .utilities,
                                                 expandedContentHeight: 0)
        XCTAssertEqual(layout.panelFrame.midX, m.frame.midX, accuracy: 1)
        // Top of the panel pinned to top of screen.
        XCTAssertEqual(layout.panelFrame.maxY, m.frame.maxY, accuracy: 1)
    }

    func testNotchlessDisplayUsesPill() {
        let m = plainScreen()
        XCTAssertFalse(m.hasNotch)
        XCTAssertEqual(NotchGeometryService.compactWidth(for: m), DesignTokens.Metrics.pillWidth)
    }

    func testExpandedIsWiderForAgents() {
        let m = notchScreen()
        let util = NotchGeometryService.layout(for: m, state: .expanded, face: .utilities,
                                               expandedContentHeight: 300)
        let agents = NotchGeometryService.layout(for: m, state: .expanded, face: .agents,
                                                 expandedContentHeight: 300)
        XCTAssertGreaterThan(agents.panelFrame.width, util.panelFrame.width)
    }

    func testExpandedHeightClamped() {
        let m = notchScreen()
        let layout = NotchGeometryService.layout(for: m, state: .expanded, face: .utilities,
                                                 expandedContentHeight: 5000)
        XCTAssertLessThanOrEqual(layout.panelFrame.height,
                                 DesignTokens.Metrics.expandedMaxHeight + NotchGeometryService.compactHeight(for: m) + 1)
    }

    func testNoNotchPeekAnchorsBelowMenuBarAtVisibleTopCenter() {
        let metrics = DisplayMetrics(
            frame: CGRect(x: 100, y: 0, width: 1920, height: 1080),
            notchHeight: 0,
            notchWidth: 0,
            backingScaleFactor: 1,
            visibleFrame: CGRect(x: 100, y: 0, width: 1920, height: 1055)
        )

        let layout = NotchGeometryService.layout(
            for: metrics,
            state: .peeking,
            face: .utilities,
            expandedContentHeight: 0,
            compactExtraWidth: 420
        )

        XCTAssertEqual(layout.panelFrame.midX, metrics.frame.midX, accuracy: 1)
        XCTAssertEqual(layout.panelFrame.maxY, metrics.visibleFrame!.maxY, accuracy: 1)
        XCTAssertTrue(layout.panelFrame.width > 0)
        XCTAssertTrue(layout.panelFrame.height > 0)
    }

    func testFrontmostWindowSelectsExternalDisplayByGreatestIntersection() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        ]
        let frontmostWindow = CGRect(x: 1700, y: 100, width: 1000, height: 700)

        XCTAssertEqual(
            DisplaySelection.index(
                forFrontmostWindow: frontmostWindow,
                screenFrames: screens
            ),
            1
        )
    }

    func testPeekHitTestingPassesThroughTransparentRegions() {
        let visible = CGRect(x: 100, y: 900, width: 600, height: 100)

        XCTAssertFalse(PeekHitTestPolicy.captures(
            CGPoint(x: 90, y: 950),
            visibleFrame: visible,
            bottomCornerRadius: 20
        ))
        XCTAssertFalse(PeekHitTestPolicy.captures(
            CGPoint(x: 101, y: 901),
            visibleFrame: visible,
            bottomCornerRadius: 20
        ))
        XCTAssertTrue(PeekHitTestPolicy.captures(
            CGPoint(x: 400, y: 950),
            visibleFrame: visible,
            bottomCornerRadius: 20
        ))
    }
}

@MainActor
final class PeekPanelContractTests: XCTestCase {
    func testNonactivatingHostAcceptsFirstMouseForPeekButtons() {
        let host = PassthroughHostingView(rootView: AnyView(EmptyView()))

        XCTAssertTrue(host.acceptsFirstMouse(for: nil))
    }

    func testPanelReceivesMouseMovementWithoutBecomingKey() {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 120))

        XCTAssertTrue(panel.acceptsMouseMovedEvents)
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testPanelRemainsNonactivatingAndSpaceCompatible() {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 120))

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }
}

final class ApprovalPeekCompactPolicyTests: XCTestCase {
    func testDismissedPeekForcesPhysicalIdleWithoutMutatingLiveLayout() {
        let original = LiveActivityLayout(
            leading: WingSlot(symbol: "timer", text: "10:00"),
            trailing: WingSlot(symbol: "cpu", text: "Agent")
        )

        let effective = ApprovalPeekCompactPolicy.effectiveLayout(
            original,
            isSuppressed: true
        )

        XCTAssertTrue(effective.isEmpty)
        XCTAssertFalse(original.isEmpty)
    }

    func testNormalCompactLayoutRemainsUnchanged() {
        let original = LiveActivityLayout(
            leading: WingSlot(symbol: "timer", text: "10:00")
        )

        XCTAssertEqual(
            ApprovalPeekCompactPolicy.effectiveLayout(original, isSuppressed: false),
            original
        )
    }
}

final class CompactStatusCoordinatorTests: XCTestCase {

    func testApprovalBeatsEverything() {
        var input = CompactStatusInputs()
        input.attentionSession = .init(label: "Codex", status: .waitingForApproval)
        input.timerJustFinished = true
        input.pomodoroRunningRemaining = "12:00"
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .agentApproval(label: "Codex"))
    }

    func testInputBeatsTimer() {
        var input = CompactStatusInputs()
        input.attentionSession = .init(label: "Claude", status: .waitingForInput)
        input.timerJustFinished = true
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .agentInput(label: "Claude"))
    }

    func testPriorityCascade() {
        var input = CompactStatusInputs()
        input.timerJustFinished = true
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .timerFinished)

        input.timerJustFinished = false
        input.recentlyFinishedSession = .init(label: "Codex", status: .completed)
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .agentFinished(label: "Codex", failed: false))

        input.recentlyFinishedSession = nil
        input.pomodoroRunningRemaining = "05:00"
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .pomodoroRunning(remaining: "05:00"))

        input.pomodoroRunningRemaining = nil
        input.dragInProgress = true
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .dragActive)

        input.dragInProgress = false
        input.clipboardSymbol = "doc.on.clipboard"
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .clipboard(symbol: "doc.on.clipboard"))

        input.clipboardSymbol = nil
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .normal)
    }
}

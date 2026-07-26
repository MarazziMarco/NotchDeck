import XCTest
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

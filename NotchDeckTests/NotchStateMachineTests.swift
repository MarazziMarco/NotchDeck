import XCTest
@testable import NotchDeck

final class NotchStateMachineTests: XCTestCase {

    func testHoverPeeksThenRetracts() {
        var m = NotchStateMachine()
        XCTAssertEqual(m.presentation, .compact)
        XCTAssertTrue(m.apply(.hoverBegan))
        XCTAssertEqual(m.presentation, .peeking)
        XCTAssertTrue(m.apply(.hoverEnded))
        XCTAssertEqual(m.presentation, .compact)
    }

    func testClickExpandsAndStaysOnHoverEnd() {
        var m = NotchStateMachine()
        m.apply(.clicked)
        XCTAssertEqual(m.presentation, .expanded)
        // Hover ending must NOT collapse a click-opened panel.
        XCTAssertFalse(m.apply(.hoverEnded))
        XCTAssertEqual(m.presentation, .expanded)
    }

    func testLockPreventsExpansion() {
        var m = NotchStateMachine()
        m.apply(.setLocked(true))
        XCTAssertFalse(m.apply(.clicked))
        XCTAssertEqual(m.presentation, .compact)
        m.apply(.setLocked(false))
        XCTAssertTrue(m.apply(.clicked))
        XCTAssertEqual(m.presentation, .expanded)
    }

    func testDragEntersExpandsToUtilities() {
        var m = NotchStateMachine()
        m.switchFace(to: .agents)
        m.apply(.dragEntered)
        XCTAssertEqual(m.presentation, .expanded)
        XCTAssertEqual(m.face, .utilities)
    }

    func testEscapeAndOutsideCollapse() {
        var m = NotchStateMachine()
        m.apply(.clicked)
        m.apply(.escapePressed)
        XCTAssertEqual(m.presentation, .compact)
        m.apply(.clicked)
        m.apply(.outsideClicked)
        XCTAssertEqual(m.presentation, .compact)
    }

    func testRedundantTransitionsAreNoOps() {
        var m = NotchStateMachine()
        XCTAssertTrue(m.apply(.requestCompact) == false) // already compact
        m.apply(.clicked)
        XCTAssertFalse(m.apply(.clicked))                // already expanded
    }

    func testLockBlocksRequestExpandButAllowsCompact() {
        var m = NotchStateMachine()
        m.apply(.requestExpand(.agents))
        XCTAssertEqual(m.presentation, .expanded)
        // Pinned open: a lock is set while expanded (the "pin" gesture).
        m.apply(.setLocked(true))
        XCTAssertEqual(m.presentation, .expanded)
        // A fresh expand request while locked is a no-op...
        XCTAssertFalse(m.apply(.requestExpand(.utilities)))
        // ...but an explicit compact (Escape / outside click) still collapses.
        XCTAssertTrue(m.apply(.requestCompact))
        XCTAssertEqual(m.presentation, .compact)
    }

    func testRequestExpandSetsFace() {
        var m = NotchStateMachine()
        m.apply(.requestExpand(.agents))
        XCTAssertEqual(m.face, .agents)
    }

    func testSwitchFaceToggles() {
        var m = NotchStateMachine()
        XCTAssertEqual(m.face, .utilities)
        XCTAssertTrue(m.switchFace())
        XCTAssertEqual(m.face, .agents)
        XCTAssertFalse(m.switchFace(to: .agents))        // no change
    }
}

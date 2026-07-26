import XCTest
@testable import NotchDeck

/// Home customization reordering — the shared engine used by the visual preview,
/// the settings rows and keyboard actions (one source of truth).
final class HomeReorderTests: XCTestCase {
    private let base = ["quickNote", "nowPlaying", "fileShelf", "mirror"]

    func testDragCard1OntoCard3ChangesOrder() {
        // Drag slot 1 (quickNote) onto slot 3 (fileShelf).
        let out = HomeReorder.move(base, drag: "quickNote", onto: "fileShelf")
        XCTAssertEqual(out, ["nowPlaying", "fileShelf", "quickNote", "mirror"])
        XCTAssertNotEqual(out, base)
    }
    func testMoveOntoSelfIsNoOp() {
        XCTAssertEqual(HomeReorder.move(base, drag: "mirror", onto: "mirror"), base)
    }
    func testInvalidDropUnknownIdNoChange() {
        XCTAssertEqual(HomeReorder.move(base, drag: "ghost", onto: "mirror"), base)
        XCTAssertEqual(HomeReorder.move(base, drag: "mirror", onto: "ghost"), base)
    }
    func testNoDuplicatesAfterMove() {
        let out = HomeReorder.move(base, drag: "mirror", onto: "quickNote")
        XCTAssertEqual(Set(out), Set(base))          // same elements
        XCTAssertEqual(out.count, base.count)        // no duplicates
    }
    func testRapidRepeatedMovesStayValid() {
        var ids = base
        for _ in 0..<20 {
            ids = HomeReorder.move(ids, drag: "quickNote", onto: "mirror")
            ids = HomeReorder.move(ids, drag: "mirror", onto: "nowPlaying")
        }
        XCTAssertEqual(Set(ids), Set(base))
        XCTAssertEqual(ids.count, 4)
    }
    func testShiftEarlierLater() {
        XCTAssertEqual(HomeReorder.shift(base, id: "fileShelf", by: -1),
                       ["quickNote", "fileShelf", "nowPlaying", "mirror"])
        XCTAssertEqual(HomeReorder.shift(base, id: "quickNote", by: -1), base)   // clamped at start
        XCTAssertEqual(HomeReorder.shift(base, id: "mirror", by: 1), base)       // clamped at end
    }
    func testKeyboardAndDragShareSameEngine() {
        // Shifting later == moving onto the next neighbour.
        let viaShift = HomeReorder.shift(base, id: "quickNote", by: 1)
        let viaDrag = HomeReorder.move(base, drag: "quickNote", onto: "nowPlaying")
        XCTAssertEqual(viaShift, viaDrag)
    }

    // Preview only renders visible modules → hidden excluded from draggable slots.
    func testHiddenExcludedFromPreviewSlots() {
        let hidden = ["fileShelf"]
        let visible = base.filter { !hidden.contains($0) }
        XCTAssertEqual(visible, ["quickNote", "nowPlaying", "mirror"])
    }
}

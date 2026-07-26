import XCTest
@testable import NotchDeck

/// Production File Shelf grid geometry (Home module uses EditorialFileShelf →
/// FileShelfGridCell, a compact adaptive grid — not a full-width list).
final class FileShelfGridTests: XCTestCase {
    func testCellWidthIsConstrainedNotFullModule() {
        XCTAssertLessThanOrEqual(FileShelfGrid.cellMinWidth, 112)
        XCTAssertGreaterThanOrEqual(FileShelfGrid.cellMinWidth, 80)
        XCTAssertLessThanOrEqual(FileShelfGrid.cellMaxWidth, 120)
        // A single cell is far narrower than a typical Home module width.
        XCTAssertLessThan(FileShelfGrid.cellMaxWidth, 300)
    }
    func testCellHeightConstrained() {
        XCTAssertGreaterThanOrEqual(FileShelfGrid.cellHeight, 100)
        XCTAssertLessThanOrEqual(FileShelfGrid.cellHeight, 132)
    }
    func testIconSizeInRange() {
        XCTAssertGreaterThanOrEqual(FileShelfGrid.iconSize, 52)
        XCTAssertLessThanOrEqual(FileShelfGrid.iconSize, 64)
    }
    func testMultipleColumnsAtModuleWidths() {
        // Small/Medium/Large module widths → several compact columns, never 1.
        XCTAssertGreaterThanOrEqual(FileShelfGrid.columns(forWidth: 220), 2)   // small zone
        XCTAssertGreaterThanOrEqual(FileShelfGrid.columns(forWidth: 300), 3)   // medium
        XCTAssertGreaterThanOrEqual(FileShelfGrid.columns(forWidth: 420), 4)   // large
    }
    func testColumnsGrowWithWidth() {
        XCTAssertLessThan(FileShelfGrid.columns(forWidth: 200), FileShelfGrid.columns(forWidth: 460))
    }
    func testFillsHorizontallyBeforeWrapping() {
        // With room for 4 columns, 4 items occupy one row (0 wrapped).
        let cols = FileShelfGrid.columns(forWidth: 420)
        XCTAssertGreaterThanOrEqual(cols, 4)
        let items = 4
        let rows = Int(ceil(Double(items) / Double(cols)))
        XCTAssertEqual(rows, 1)
    }
    func testEightItemsWrapToMultipleRows() {
        let cols = FileShelfGrid.columns(forWidth: 300)   // ~3 columns
        let rows = Int(ceil(8.0 / Double(cols)))
        XCTAssertGreaterThan(rows, 1)
    }
    func testNarrowStillNotSingleFullWidth() {
        // Even a narrow zone fits ≥2 compact cells unless genuinely tiny.
        XCTAssertGreaterThanOrEqual(FileShelfGrid.columns(forWidth: 200), 2)
    }
}

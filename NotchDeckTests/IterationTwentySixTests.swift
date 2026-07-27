import XCTest
import AppKit
@testable import NotchDeck

// MARK: Selection model (pure)

final class ShelfSelectionTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private var order: [UUID] { [a, b, c, d] }

    func testClickSelectsOne() {
        var s = ShelfSelection(); s.click(b)
        XCTAssertEqual(s.selected, [b]); XCTAssertEqual(s.count, 1)
        s.click(c); XCTAssertEqual(s.selected, [c])   // clears previous
    }
    func testCommandClickToggles() {
        var s = ShelfSelection(); s.click(a); s.toggle(b); s.toggle(c)
        XCTAssertEqual(s.selected, [a, b, c])
        s.toggle(b); XCTAssertEqual(s.selected, [a, c])   // toggled out
    }
    func testShiftClickRange() {
        var s = ShelfSelection(); s.click(a); s.range(to: c, order: order)
        XCTAssertEqual(s.selected, [a, b, c])
    }
    func testShiftClickWithoutAnchorIsClick() {
        var s = ShelfSelection(); s.range(to: c, order: order)
        XCTAssertEqual(s.selected, [c])
    }
    func testSelectAllAndClear() {
        var s = ShelfSelection(); s.selectAll(order)
        XCTAssertEqual(s.selected, Set(order))
        s.clear(); XCTAssertTrue(s.isEmpty)
    }
    func testPrunePrunesOnlyInvalid() {
        var s = ShelfSelection(); s.selectAll(order)
        s.prune(validIDs: [a, c])
        XCTAssertEqual(s.selected, [a, c])   // b,d dropped; a,c kept
    }
    func testDragSetSelectedDragsWholeSelectionInOrder() {
        var s = ShelfSelection(); s.click(a); s.toggle(c)
        XCTAssertEqual(s.dragSet(startingAt: c, order: order), [a, c])   // grid order
    }
    func testDragUnselectedDragsOnlyItAndSelectsIt() {
        var s = ShelfSelection(); s.click(a)
        XCTAssertEqual(s.dragSet(startingAt: c, order: order), [c])
        XCTAssertEqual(s.selected, [c])   // becomes the sole selection
    }
    func testCommandTargetsForUnselectedSelectsIt() {
        var s = ShelfSelection(); s.click(a)
        XCTAssertEqual(s.commandTargets(for: c, order: order), [c])
        XCTAssertEqual(s.selected, [c])
    }
}

// MARK: Drag safety + recovery (store)

@MainActor
final class FileShelfDragSafetyTests: XCTestCase {
    private var tmp: URL!
    private var engine: FileShelfStaging!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        engine = FileShelfStaging(root: tmp.appendingPathComponent("Shelf"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func file(_ name: String, _ body: String = "x") throws -> URL {
        let u = tmp.appendingPathComponent(name)
        try body.data(using: .utf8)!.write(to: u); return u
    }
    private func store(_ mode: FileShelfIntakeMode) -> FileShelfStore {
        let s = FileShelfStore(engine: engine); s.intakeMode = mode; return s
    }

    func testInternalDropDetection() {
        let p = NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier: ShelfDrag.typeString, visibility: .all) { done in
            done("id".data(using: .utf8), nil); return nil
        }
        XCTAssertTrue(ShelfDrag.isInternal([p]))
        XCTAssertFalse(ShelfDrag.isInternal([NSItemProvider(object: NSURL(fileURLWithPath: "/tmp/x"))]))
    }

    func testCopyKeepsStagedSource() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("a.txt")])
        let staged = s.items[0].stagedPath!
        s.completeDrag(item: s.items[0], operation: .copy)
        XCTAssertEqual(s.items.count, 1)                                   // item kept
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged))      // staged file kept
    }
    func testMoveRemovesOnlyWhenStagedGone() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("b.txt")])
        let id = s.items[0].id
        // Move reported but staged file still present (internal/failed) → keep.
        s.completeDrag(item: s.items[0], operation: .move)
        XCTAssertEqual(s.items.count, 1)
        // Now simulate the OS actually moving the staged file out, then move.
        try FileManager.default.removeItem(at: URL(fileURLWithPath: s.items[0].stagedPath!))
        s.completeGroupDrag(items: [id], operation: .move)
        XCTAssertTrue(s.items.isEmpty)                                     // removed after confirmed
    }
    func testCancelledAndNonePreserve() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("c.txt")])
        s.completeDrag(item: s.items[0], operation: [])
        XCTAssertEqual(s.items.count, 1)
    }
    func testInternalDropBackIsNoOp() throws {
        // AppKit reports [] for a within-app drop (our source mask). → keep.
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("d.txt")])
        let staged = s.items[0].stagedPath!
        s.completeDrag(item: s.items[0], operation: [])
        XCTAssertEqual(s.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged))
    }
    func testPartialGroupMove() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("g1.txt"), try file("g2.txt")])
        let ids = s.items.map(\.id)
        // Only g? move the first item's staged file out.
        try FileManager.default.removeItem(at: URL(fileURLWithPath: s.items[0].stagedPath!))
        let r = s.completeGroupDrag(items: ids, operation: .move)
        XCTAssertEqual(r.removed, 1)
        XCTAssertEqual(s.items.count, 1)   // the still-present one remains
    }
    func testReferenceModeCopyNeverDeletesOriginal() throws {
        let s = store(.keepOriginalReference)
        s.retentionPolicy = .keepUntilRemoved
        let original = try file("ref.txt")
        s.add(urls: [original])
        s.completeDrag(item: s.items[0], operation: .copy)
        XCTAssertEqual(s.items.count, 1)                                   // kept (keepUntilRemoved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))  // original untouched
    }

    // MARK: Recovery

    func testOrphanDetectedAndRecovered() throws {
        // Stage a file, then wipe the manifest to orphan it.
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("orphan.txt")])
        let stagedName = (s.items[0].stagedPath! as NSString).lastPathComponent
        JSONFileStore<[FileShelfItem]>(url: engine.manifestURL).save([])   // lose the manifest entry

        let s2 = FileShelfStore(engine: engine)   // startup auto-recovers
        XCTAssertTrue(s2.items.contains { $0.recovered && ($0.stagedPath! as NSString).lastPathComponent == stagedName })
        XCTAssertGreaterThanOrEqual(s2.recoveredCount, 1)
    }
    func testReconcileReportsMissingAndOrphansWithoutDeleting() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("keep.txt")])
        let stagedURL = URL(fileURLWithPath: s.items[0].stagedPath!)
        let report = s.reconcileReport()
        XCTAssertTrue(report.filesOnDisk.contains(stagedURL.lastPathComponent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))   // never deleted
        XCTAssertTrue(report.manifestPath.contains("manifest.json"))
    }
    func testRecoverIsIdempotent() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try file("i.txt")])
        JSONFileStore<[FileShelfItem]>(url: engine.manifestURL).save([])
        let s2 = FileShelfStore(engine: engine)
        let before = s2.items.count
        XCTAssertEqual(s2.recoverMissingItems(), 0)   // nothing new to recover
        XCTAssertEqual(s2.items.count, before)
    }
}

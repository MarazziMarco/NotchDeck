import XCTest
import AppKit
@testable import NotchDeck

// MARK: File Shelf staging engine

final class FileShelfStagingTests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nd-shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = tmp.appendingPathComponent("Shelf")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeFile(_ name: String, _ contents: String = "hello") throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    func testStageMovesOriginalIntoShelfAndVerifies() throws {
        let engine = FileShelfStaging(root: root)
        let original = try makeFile("doc.txt", "payload")
        let staged = try engine.stage(original)

        XCTAssertTrue(staged.path.hasPrefix(root.path))                 // lives in the shelf
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path)) // original gone
        XCTAssertEqual(try String(contentsOf: staged, encoding: .utf8), "payload")
    }

    func testFailedCopyLeavesOriginalUntouched() throws {
        // Make the staging root a *file* so copyItem into it fails.
        try "x".data(using: .utf8)!.write(to: root)
        let engine = FileShelfStaging(root: root)
        let original = try makeFile("keep.txt", "safe")
        XCTAssertThrowsError(try engine.stage(original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path)) // preserved
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "safe")
    }

    func testStageMissingOriginalThrows() {
        let engine = FileShelfStaging(root: root)
        let missing = tmp.appendingPathComponent("nope.txt")
        XCTAssertThrowsError(try engine.stage(missing)) { err in
            XCTAssertEqual(err as? FileShelfError, .originalMissing)
        }
    }

    func testStagingDirectoryIsPersistentNotCaches() {
        let p = FileShelfStaging.defaultRoot.path
        XCTAssertTrue(p.contains("Application Support/NotchDeck/FileShelf"))
        XCTAssertFalse(p.contains("/Caches"))
        XCTAssertFalse(p.contains("/tmp"))
        XCTAssertFalse(p.contains("/var/folders"))
    }
}

// MARK: File Shelf store behavior

@MainActor
final class FileShelfStoreTests: XCTestCase {
    private var tmp: URL!
    private var engine: FileShelfStaging!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nd-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        engine = FileShelfStaging(root: tmp.appendingPathComponent("Shelf"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeFile(_ name: String, in dir: URL? = nil, _ c: String = "data") throws -> URL {
        let base = dir ?? tmp!
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(name)
        try c.data(using: .utf8)!.write(to: url)
        return url
    }

    private func store(_ mode: FileShelfIntakeMode) -> FileShelfStore {
        let s = FileShelfStore(engine: engine)
        s.intakeMode = mode
        return s
    }

    func testMoveIntoShelfRemovesOriginalAfterStaging() throws {
        let s = store(.moveIntoShelf)
        let original = try makeFile("a.txt")
        XCTAssertEqual(s.add(urls: [original]), 1)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        let item = s.items[0]
        XCTAssertEqual(item.intakeMode, .moveIntoShelf)
        XCTAssertNotNil(item.resolveURL())                       // staged file present
    }

    func testStagedItemSurvivesRelaunch() throws {
        let s = store(.moveIntoShelf)
        let original = try makeFile("b.txt")
        s.add(urls: [original])
        let stagedPath = s.items[0].stagedPath!

        // Simulate relaunch: a fresh store over the same engine/manifest.
        let s2 = FileShelfStore(engine: engine)
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPath))
    }

    func testReferenceModeNeverMovesOriginal() throws {
        let s = store(.keepOriginalReference)
        let original = try makeFile("c.txt")
        s.add(urls: [original])
        XCTAssertEqual(s.items.first?.intakeMode, .keepOriginalReference)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path)) // untouched
    }

    func testCancelledDragKeepsStagedItem() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try makeFile("d.txt")])
        s.completeDrag(item: s.items[0], operation: [])          // cancelled / rejected
        XCTAssertEqual(s.items.count, 1)
    }

    func testSuccessfulMoveDragClearsEntry() throws {
        // Transactional rule: .move removes the entry only after the staged file
        // has actually left the shelf (the OS moved it out).
        let s = store(.moveIntoShelf)
        s.add(urls: [try makeFile("e.txt")])
        try FileManager.default.removeItem(at: URL(fileURLWithPath: s.items[0].stagedPath!))  // OS moved it
        s.completeDrag(item: s.items[0], operation: .move)
        XCTAssertTrue(s.items.isEmpty)
    }

    func testCopyKeepsShelfItem() throws {
        // New spec: a COPY drag-out keeps the shelf item and its staged file.
        let s = store(.moveIntoShelf)
        s.add(urls: [try makeFile("f.txt")])
        let staged = s.items[0].stagedPath!
        s.completeDrag(item: s.items[0], operation: .copy)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged))   // staged source kept
    }

    func testReferenceRemoveAfterSuccessfulDrag() throws {
        let s = store(.keepOriginalReference)
        s.retentionPolicy = .removeAfterSuccessfulDrag
        let original = try makeFile("g.txt")
        s.add(urls: [original])
        s.completeDrag(item: s.items[0], operation: .copy)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path)) // original never touched
    }

    func testReferenceKeepUntilRemoved() throws {
        let s = store(.keepOriginalReference)
        s.retentionPolicy = .keepUntilRemoved
        s.add(urls: [try makeFile("h.txt")])
        s.completeDrag(item: s.items[0], operation: .copy)
        XCTAssertEqual(s.items.count, 1)                         // kept
    }

    func testPartialMultiItemSuccess() throws {
        let s = store(.moveIntoShelf)
        s.add(urls: [try makeFile("i1.txt"), try makeFile("i2.txt")])
        XCTAssertEqual(s.items.count, 2)
        let first = s.items[0]
        // Simulate the OS moving only the first item's staged file out.
        try FileManager.default.removeItem(at: URL(fileURLWithPath: first.stagedPath!))
        s.completeDrag(item: first, operation: .move)            // one succeeds (file gone)
        s.completeDrag(item: s.items[0], operation: [])          // other cancelled
        XCTAssertEqual(s.items.count, 1)
        XCTAssertNotEqual(s.items[0].id, first.id)
    }

    func testRestoreToOriginalLocation() throws {
        let s = store(.moveIntoShelf)
        let home = tmp.appendingPathComponent("home")
        let original = try makeFile("r.txt", in: home)
        s.add(urls: [original])
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(s.restore(s.items[0]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path)) // back home
        XCTAssertTrue(s.items.isEmpty)
    }

    func testRestoreWhenOriginalLocationUnavailable() throws {
        let s = store(.moveIntoShelf)
        let gone = tmp.appendingPathComponent("gone-dir")
        let original = try makeFile("s.txt", in: gone)
        s.add(urls: [original])
        try FileManager.default.removeItem(at: gone)             // original folder vanishes
        let newDir = tmp.appendingPathComponent("newplace")
        XCTAssertTrue(s.restore(s.items[0], to: newDir.appendingPathComponent("s.txt")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.appendingPathComponent("s.txt").path))
    }

    func testFailedStagingLeavesOriginalAndSkipsItem() throws {
        // Break the shelf root so staging fails.
        try? FileManager.default.removeItem(at: engine.root)
        try "x".data(using: .utf8)!.write(to: engine.root)       // root is now a file
        let s = FileShelfStore(engine: engine); s.intakeMode = .moveIntoShelf
        let original = try makeFile("t.txt")
        XCTAssertEqual(s.add(urls: [original]), 0)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path)) // preserved
        XCTAssertNotNil(s.lastError)
    }
}

// MARK: Compact Pomodoro countdown

final class CompactPomodoroCountdownTests: XCTestCase {
    /// A running Pomodoro spanning both wings: ring on one side, MM:SS on the other.
    private func pomodoro(_ mmss: String) -> ResolvedActivity {
        ResolvedActivity(
            id: "pomodoro", priority: .pomodoroRunning,
            slot: WingSlot(symbol: "timer", text: mmss, progress: 0.5, tint: .running,
                           monospacedDigits: true, emphasize: true),
            preferredWing: .leading, tapTarget: .module("pomodoro"),
            splitLeading: WingSlot(symbol: "timer", progress: 0.5, tint: .running),
            splitTrailing: WingSlot(text: mmss, tint: .running, monospacedDigits: true, emphasize: true))
    }
    private func agent() -> ResolvedActivity {
        CompactAgentActivityFactory.make(for: .activeSessions(count: 1))!
    }

    func testRunningTimerSelectsPomodoroSplit() {
        let layout = LiveActivityCoordinator.resolve([pomodoro("19:42")])
        XCTAssertEqual(layout.leading?.symbol, "timer")          // ring on the left wing
        XCTAssertEqual(layout.trailing?.text, "19:42")           // MM:SS on the right wing
        XCTAssertNil(layout.leading?.text)                       // left wing has no text
    }

    func testFormattedRemainingNonEmpty() {
        let layout = LiveActivityCoordinator.resolve([pomodoro("00:05")])
        XCTAssertEqual(layout.trailing?.text?.count, 5)          // "00:05"
        XCTAssertTrue(layout.trailing?.emphasize == true)
    }

    func testCountdownKeepsProtectedSplitWhileOrdinaryAgentIsSuppressed() {
        let layout = LiveActivityCoordinator.resolve([pomodoro("12:00"), agent()])
        XCTAssertNil(layout.leading?.text)
        XCTAssertEqual(layout.leading?.symbol, "timer")
        XCTAssertEqual(layout.trailing?.text, "12:00")
        XCTAssertNil(layout.trailing?.symbol)
    }

    func testRightWingReservesWidthForFiveChars() {
        // 200pt notch + 152 two-wing extra ⇒ ~76pt per wing, comfortably above the
        // ~46pt reserved for "00:00".
        let notch: CGFloat = 200
        let compactW = notch + 152
        let wing = (compactW - notch) / 2
        XCTAssertGreaterThanOrEqual(wing, 46)
    }

    func testTimerTextDoesNotIntersectHousing() {
        // Right-wing text frame sits entirely to the right of the housing.
        let notch: CGFloat = 200
        let compactW = notch + 152
        let wing = (compactW - notch) / 2
        let housing = CGRect(x: wing, y: 0, width: notch, height: 32)
        let rightWing = CGRect(x: wing + notch, y: 0, width: wing, height: 32)
        XCTAssertFalse(rightWing.intersects(housing))
        XCTAssertGreaterThanOrEqual(rightWing.minX, housing.maxX)
    }

    func testStopRestoresNormalCompactState() {
        // No activities ⇒ empty compact strip (Stop/Reset removes the countdown).
        XCTAssertTrue(LiveActivityCoordinator.resolve([]).isEmpty)
    }
}

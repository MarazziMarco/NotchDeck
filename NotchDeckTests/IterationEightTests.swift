import XCTest
@testable import NotchDeck

final class GridSolverTests: XCTestCase {
    private func item(_ id: String, _ w: Int, _ h: Int, col: Int? = nil, row: Int? = nil) -> GridSolver.Item {
        GridSolver.Item(id: id, w: w, h: h, preferredCol: col, preferredRow: row)
    }

    func testNoOverlapAndDeterministic() {
        let items = [item("a", 4, 2), item("b", 4, 2), item("c", 2, 2)]
        let r1 = GridSolver.solve(items: items, columns: 8)
        let r2 = GridSolver.solve(items: items, columns: 8)
        XCTAssertEqual(r1, r2)   // deterministic
        for i in r1.cells.indices { for j in (i+1)..<r1.cells.count {
            XCTAssertFalse(GridSolver.overlaps(r1.cells[i], r1.cells[j]))
        } }
    }

    func testStaysWithinColumns() {
        let r = GridSolver.solve(items: [item("a", 6, 2), item("b", 6, 2)], columns: 6)
        for c in r.cells { XCTAssertLessThanOrEqual(c.maxX, 6) }
    }

    func testReflowToNextRow() {
        // Two 4-wide widgets on an 8-col grid share row 0; a third wraps to row 2.
        let r = GridSolver.solve(items: [item("a", 4, 2), item("b", 4, 2), item("c", 4, 2)], columns: 8)
        let c = r.cells.first { $0.id == "c" }!
        XCTAssertEqual(c.row, 2)
        XCTAssertEqual(c.col, 0)
    }

    func testPreferredCellHonoredWhenFree() {
        let r = GridSolver.solve(items: [item("a", 2, 2, col: 4, row: 0)], columns: 8)
        let a = r.cells.first!
        XCTAssertEqual(a.col, 4); XCTAssertEqual(a.row, 0)
    }

    func testCollisionFallsBackToFirstFree() {
        // b prefers the same cell a took → b relocates, no overlap.
        let r = GridSolver.solve(items: [item("a", 2, 2, col: 0, row: 0),
                                         item("b", 2, 2, col: 0, row: 0)], columns: 8)
        XCTAssertFalse(GridSolver.overlaps(r.cells[0], r.cells[1]))
    }

    func testOverflowToSecondPage() {
        // Fill more than maxRows*columns → later widgets go to page 1.
        let items = (0..<20).map { item("m\($0)", 2, 2) }
        let r = GridSolver.solve(items: items, columns: 6, maxRows: 4)
        XCTAssertGreaterThanOrEqual(r.pageCount, 2)
        XCTAssertTrue(r.cells.contains { $0.page >= 1 })
    }

    func testDropSnapping() {
        let (col, row) = GridSolver.cell(forDropAt: CGPoint(x: 250, y: 90),
                                         in: CGSize(width: 800, height: 200), columns: 8, rows: 4)
        XCTAssertEqual(col, 2)   // 250 / (800/8=100) = 2
        XCTAssertEqual(row, 1)   // 90 / (200/4=50) = 1
    }

    func testWidgetSizeCells() {
        XCTAssertEqual(DashboardWidgetSize.compact.cells.w, 2)
        XCTAssertEqual(DashboardWidgetSize.large.cells.h, 3)
    }

    func testColumnsPerLayoutClass() {
        XCTAssertEqual(DashboardGrid.columns(for: .compact), 6)
        XCTAssertEqual(DashboardGrid.columns(for: .regular), 8)
        XCTAssertEqual(DashboardGrid.columns(for: .spacious), 10)
    }
}

@MainActor
final class DashboardModelTests: XCTestCase {
    private func make() -> (DashboardModel, ModuleRegistry, SettingsStore) {
        let settings = SettingsStore.inMemory()
        let registry = ModuleRegistry(modules: [ClipboardModule(), PomodoroModule(), MirrorModule(),
                                                QuickNoteModule(), NowPlayingModule(), FileShelfModule()],
                                      settings: settings)
        return (DashboardModel(settings: settings, registry: registry), registry, settings)
    }

    func testAddPlacesWidgetAndRemove() {
        let (m, _, _) = make()
        m.applyPreset(.minimal, for: .regular)
        let before = m.placements(for: .regular).count
        m.addWidget("mirror", for: .regular)
        XCTAssertEqual(m.placements(for: .regular).count, before + 1)
        m.remove("mirror", for: .regular)
        XCTAssertEqual(m.placements(for: .regular).count, before)
    }

    func testResizeValidationRejectsUnsupported() {
        let (m, _, _) = make()
        m.applyPreset(.balanced, for: .regular)
        // Mirror supports [.compact,.small,.medium] — .large is invalid.
        XCTAssertFalse(m.isSizeValid("mirror", .large))
        m.setSize("mirror", .large, for: .regular)
        XCTAssertNotEqual(m.placements(for: .regular).first { $0.moduleID == "mirror" }?.size, .large)
        // A supported size is applied.
        m.setSize("mirror", .medium, for: .regular)
        XCTAssertEqual(m.placements(for: .regular).first { $0.moduleID == "mirror" }?.size, .medium)
    }

    func testPerLayoutClassSnapshotsIndependent() {
        let (m, _, _) = make()
        m.applyPreset(.minimal, for: .compact)
        m.applyPreset(.media, for: .spacious)
        XCTAssertNotEqual(m.placements(for: .compact).map(\.moduleID),
                          m.placements(for: .spacious).map(\.moduleID))
    }

    func testMoveReordersDeterministically() {
        let (m, _, _) = make()
        m.applyPreset(.balanced, for: .regular)
        let ids = m.placements(for: .regular).map(\.moduleID)
        let last = ids.last!
        m.move(last, toOrder: 0, for: .regular)
        XCTAssertEqual(m.placements(for: .regular).first?.moduleID, last)
    }

    func testResetClearsCustomPlacements() {
        let (m, _, _) = make()
        m.applyPreset(.media, for: .regular)
        XCTAssertTrue(m.hasCustomPlacements(for: .regular))
        m.reset(for: .regular)
        XCTAssertFalse(m.hasCustomPlacements(for: .regular))
    }

    func testResolvedProducesNoOverlap() {
        let (m, _, _) = make()
        m.applyPreset(.balanced, for: .regular)
        let cells = m.resolved(for: .regular).cells
        for i in cells.indices { for j in (i+1)..<cells.count {
            XCTAssertFalse(GridSolver.overlaps(cells[i], cells[j]))
        } }
    }
}

@MainActor
final class PomodoroStyleTests: XCTestCase {
    func testStyleDoesNotMutateEngine() {
        let settings = SettingsStore.inMemory()
        let service = PomodoroService(config: PomodoroConfig(),
                                      notifications: MockNotificationService(),
                                      fileName: "style-\(UUID().uuidString).json")
        service.start()
        let before = service.engine
        settings.settings.pomodoroWidgetStyle = .monochrome   // appearance only
        XCTAssertEqual(service.engine, before)                // engine untouched
        XCTAssertTrue(service.engine.isRunning)
    }
}

@MainActor
final class CustomizePinTests: XCTestCase {
    func testCustomizingKeepsOpenWithoutPinning() {
        let state = AppState(settings: SettingsStore.inMemory())
        state.expand()
        state.isCustomizingDashboard = true
        XCTAssertTrue(state.shouldStayOpen)      // stays open
        XCTAssertFalse(state.isPinnedByUser)     // but never pins
    }
}

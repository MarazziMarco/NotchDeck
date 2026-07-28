import XCTest
@testable import NotchDeck

final class LiveActivityResolveTests: XCTestCase {
    private func agentsRunning(count: Int = 1) -> ResolvedActivity {
        CompactAgentActivityFactory.make(for: .activeSessions(count: count))!
    }
    private func pomodoro() -> ResolvedActivity {
        ResolvedActivity(id: "pomodoro", priority: .pomodoroRunning,
                         slot: WingSlot(symbol: "timer", text: "24:37", progress: 0.3, tint: .running),
                         preferredWing: .leading, tapTarget: .module("pomodoro"))
    }
    private func approval() -> ResolvedActivity {
        ResolvedActivity(id: "agents", priority: .approval,
                         slot: WingSlot(symbol: "cpu", tint: .approval),
                         preferredWing: .leading, attention: true,
                         tapTarget: .face(.agents), exclusive: true, exclusiveLabel: "Allow?")
    }

    func testEmptyWhenNoActivities() {
        XCTAssertTrue(LiveActivityCoordinator.resolve([]).isEmpty)
    }

    func testApprovalOverridesRunning() {
        let layout = LiveActivityCoordinator.resolve([agentsRunning(), approval()])
        XCTAssertTrue(layout.attention)
        XCTAssertEqual(layout.leading?.symbol, "cpu")
        XCTAssertEqual(layout.trailing?.text, "Allow?")
        XCTAssertEqual(layout.tapTarget, .face(.agents))
    }

    func testTimerAndAgentsUseSeparateWings() {
        let layout = LiveActivityCoordinator.resolve([pomodoro(), agentsRunning()])
        XCTAssertEqual(layout.leading?.symbol, "timer")   // pomodoro leading
        XCTAssertEqual(
            layout.trailing?.compactAgentIndicator,
            .activeSessions(count: 1)
        )
    }

    func testPriorityOrder() {
        let media = ResolvedActivity(id: "np", priority: .media,
                                     slot: WingSlot(symbol: "music.note"), preferredWing: .leading)
        // Pomodoro (3) outranks media (5) for the primary/leading slot.
        let layout = LiveActivityCoordinator.resolve([media, pomodoro()])
        XCTAssertEqual(layout.leading?.symbol, "timer")
    }

    func testMultipleAgentsUseOneTypedAggregateCount() {
        let layout = LiveActivityCoordinator.resolve([agentsRunning(count: 3)])
        XCTAssertEqual(layout.compactAgentIndicator, .activeSessions(count: 3))
        XCTAssertNil(layout.trailing?.badge)
        XCTAssertNil(layout.trailing?.text)
    }
}

@MainActor
final class AgentsLiveSourceTests: XCTestCase {
    func testInactiveStoreProducesNoActivity() {
        let store = AgentSessionStore(fileName: "la-\(UUID().uuidString).json")
        XCTAssertNil(store.currentActivity())   // inactive modules don't occupy compact
    }

    func testRunningAgentsUseOneNormalizedIndicator() {
        let store = AgentSessionStore(fileName: "la-\(UUID().uuidString).json")
        for i in 0..<3 {
            var s = AgentSession(provider: .codex, title: "s\(i)", projectPath: "/tmp", status: .running)
            s.isBridgeConnected = true
            store.upsert(s)
        }
        let activity = store.currentActivity()
        XCTAssertEqual(activity?.priority, .agentsRunning)
        XCTAssertEqual(activity?.slot.compactAgentIndicator, .activeSessions(count: 3))
        XCTAssertNil(activity?.slot.badge)
        XCTAssertNil(activity?.slot.text)
        XCTAssertEqual(activity?.preferredWing, .trailing)
    }

    func testApprovalIsExclusive() {
        let store = AgentSessionStore(fileName: "la-\(UUID().uuidString).json")
        // A genuine approval requires a live PendingApproval (from a PermissionRequest),
        // not merely waitingForApproval status.
        let e = TerminalAgentEvent(type: .permissionRequested, provider: .claudeCode,
                                   sessionID: "S", cwd: "/tmp", timestamp: Date().timeIntervalSince1970,
                                   requestID: "R1")
        let session = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e, now: Date())
        store.upsert(session)
        let activity = store.currentActivity()
        XCTAssertEqual(activity?.priority, .approval)
        XCTAssertTrue(activity?.exclusive ?? false)
    }
}

@MainActor
final class DashboardTests: XCTestCase {
    func testReflowPacksIntoRows() {
        // large(4), small(1), small(1), medium(2) → [ [large], [small,small,medium] ]
        let rows = DashboardPacking.rows(spans: [4, 1, 1, 2], columns: 4)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], [0])
        XCTAssertEqual(rows[1], [1, 2, 3])
    }

    func testReflowAfterResize() {
        // Three mediums: [med,med],[med]
        let rows = DashboardPacking.rows(spans: [2, 2, 2], columns: 4)
        XCTAssertEqual(rows.map(\.count), [2, 1])
    }

    func testSizePersistsAndFavoritesOrder() {
        let settings = SettingsStore.inMemory()
        let registry = ModuleRegistry(modules: [ClipboardModule(), PomodoroModule(), MirrorModule()],
                                      settings: settings)
        let clip = registry.module(id: "clipboard")!
        registry.setSize(clip, .small)
        XCTAssertEqual(registry.size(for: clip), .small)
        XCTAssertEqual(settings.settings.homeSizes["clipboard"], .small)

        registry.setHomeOrder(["mirror", "clipboard"])
        XCTAssertEqual(registry.homeModules.map(\.id), ["mirror", "clipboard"])
    }

    func testAddRemoveHome() {
        let settings = SettingsStore.inMemory()
        let registry = ModuleRegistry(modules: [ClipboardModule(), QuickNoteModule()], settings: settings)
        let note = registry.module(id: "quickNote")!   // not a default favorite
        XCTAssertFalse(registry.isHomeFavorite(note))
        registry.addToHome(note)
        XCTAssertTrue(registry.isHomeFavorite(note))
        registry.removeFromHome(note)
        XCTAssertFalse(registry.isHomeFavorite(note))
    }
}

@MainActor
final class FocusNavigationTests: XCTestCase {
    func testFocusModuleDoesNotPin() {
        let state = AppState(settings: SettingsStore.inMemory())
        state.expand()
        state.focusModule("clipboard")
        XCTAssertEqual(state.focusedModuleID, "clipboard")
        XCTAssertFalse(state.isPinnedByUser)          // compact-activity/dashboard tap never pins
        XCTAssertFalse(state.showingModuleLibrary)
    }

    func testCollapseClearsFocusButKeepsUnpinned() {
        let state = AppState(settings: SettingsStore.inMemory())
        state.expand(); state.focusModule("mirror")
        state.compact()
        XCTAssertNil(state.focusedModuleID)           // returns to Home
        XCTAssertFalse(state.isPinnedByUser)
    }

}

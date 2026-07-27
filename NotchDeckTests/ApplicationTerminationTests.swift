import XCTest
@testable import NotchDeck

@MainActor
private final class FakeApplicationTerminator: ApplicationTerminating {
    private(set) var terminationRequests = 0
    func terminateApplication() { terminationRequests += 1 }
}

final class ApplicationTerminationTests: XCTestCase {
    func testQuitActionExistsOnceInPersistentSettingsFooter() {
        XCTAssertEqual(SettingsPersistentAction.allCases, [.quit])
        XCTAssertEqual(SettingsPersistentAction.quit.label, "Quit NotchDeck")
        XCTAssertEqual(SettingsPersistentAction.quit.icon, "power")
        for section in SettingsRootView.Section.allCases {
            XCTAssertTrue(SettingsPersistentAction.actions(in: section).isEmpty,
                          "quit must not be duplicated in \(section.rawValue)")
        }
    }

    @MainActor
    func testCoordinatorRequestsApplicationTerminationWithoutTouchingAWindow() {
        let application = FakeApplicationTerminator()
        let coordinator = ApplicationTerminationCoordinator(application: application)

        coordinator.requestTermination()

        XCTAssertEqual(application.terminationRequests, 1)
    }

    func testQuitActionHasAccessibleDestructiveSemantics() {
        XCTAssertEqual(SettingsPersistentAction.quit.accessibilityLabel, "Quit NotchDeck")
        XCTAssertTrue(SettingsPersistentAction.quit.isDestructive)
    }

    func testShutdownSequenceFlushesSettingsStopsRefreshAndRequestsBridgeShutdown() {
        var events: [String] = []
        ApplicationShutdownSequence.perform(.init(
            flushSettings: { events.append("flush") },
            stopModuleRefreshLoops: { events.append("modules") },
            stopTransientObservers: { events.append("observers") },
            endFileShelfSession: { events.append("shelf") },
            resetPomodoro: { events.append("pomodoro") },
            requestBridgeShutdown: { events.append("bridge") }))

        XCTAssertEqual(events, [
            "flush", "modules", "observers", "shelf", "pomodoro", "bridge",
        ])
    }

    @MainActor
    func testSystemPulseRefreshLoopStopsForApplicationTermination() async {
        let service = SystemPulseService(provider: FakeSystemMetricsProvider(.empty))
        service.activate()
        XCTAssertTrue(service.isPolling)

        NotificationCenter.default.post(name: .notchDeckWillTerminate, object: nil)
        await Task.yield()

        XCTAssertFalse(service.isPolling)
    }

    @MainActor
    func testShutdownFlushPersistsCurrentSettings() {
        let suite = "ApplicationTerminationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.settings.showHomeDividers = false

        ApplicationShutdownSequence.perform(.init(
            flushSettings: store.saveNow,
            stopModuleRefreshLoops: {},
            stopTransientObservers: {},
            endFileShelfSession: {},
            resetPomodoro: {},
            requestBridgeShutdown: {}))

        XCTAssertFalse(SettingsStore(defaults: defaults).settings.showHomeDividers)
    }

    @MainActor
    func testShutdownLeavesStagedFileShelfItemsUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationTerminationTests-\(UUID().uuidString)")
        let sourceDirectory = root.appendingPathComponent("source")
        let shelfDirectory = root.appendingPathComponent("shelf")
        try FileManager.default.createDirectory(
            at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = sourceDirectory.appendingPathComponent("important.txt")
        try Data("keep me".utf8).write(to: source)
        let shelf = FileShelfStore(engine: FileShelfStaging(root: shelfDirectory))
        XCTAssertEqual(shelf.add(urls: [source]), 1)
        let staged = try XCTUnwrap(shelf.items.first?.resolveURL())

        ApplicationShutdownSequence.perform(.init(
            flushSettings: {},
            stopModuleRefreshLoops: {},
            stopTransientObservers: {},
            endFileShelfSession: shelf.handleSessionEnd,
            resetPomodoro: {},
            requestBridgeShutdown: {}))

        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }
}

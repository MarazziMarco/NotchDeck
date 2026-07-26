import XCTest
@testable import NotchDeck

@MainActor
final class DefaultsAndGroupingTests: XCTestCase {
    private func makeRegistry() -> (ModuleRegistry, SettingsStore) {
        let settings = SettingsStore.inMemory()
        let modules: [NotchModule] = [ClipboardModule(), FileShelfModule(), MirrorModule(),
            PomodoroModule(), QuickNoteModule(), NowPlayingModule(),
            DownloadsModule(), ScreenshotModule(), BatteryModule()]
        return (ModuleRegistry(modules: modules, settings: settings), settings)
    }

    func testAllModulesEnabledByDefault() {
        let (registry, _) = makeRegistry()
        for module in registry.allModules {
            XCTAssertTrue(registry.isEnabled(module), "\(module.id) should be enabled by default")
        }
    }

    func testPomodoroEnabledByDefault() {
        let (registry, _) = makeRegistry()
        let pomo = registry.module(id: "pomodoro")!
        XCTAssertTrue(registry.isEnabled(pomo))
        XCTAssertTrue(pomo.defaultEnabled)
    }

    func testHomeGroupDefault() {
        let (registry, _) = makeRegistry()
        let ids = Set(registry.modules(in: .home).map(\.id))
        XCTAssertEqual(ids, ["fileShelf", "mirror", "quickNote", "nowPlaying"])
        XCTAssertFalse(ids.contains("clipboard"))   // clipboard is Files, not Home
        XCTAssertFalse(ids.contains("pomodoro"))    // pomodoro is Focus
    }

    func testFocusGroupIsPrimarilyPomodoro() {
        let (registry, _) = makeRegistry()
        XCTAssertEqual(registry.modules(in: .focus).map(\.id), ["pomodoro"])
    }

    func testFilesGroupComposition() {
        // Batteries moved to More in iteration 11; Files = Clipboard/Downloads/Screen.
        let (registry, _) = makeRegistry()
        let ids = Set(registry.modules(in: .files).map(\.id))
        XCTAssertEqual(ids, ["clipboard", "downloads", "screenshot"])
        XCTAssertTrue(registry.modules(in: .more).contains { $0.id == "battery" })
    }

    func testNoDuplicateAcrossGroups() {
        let (registry, _) = makeRegistry()
        var seen = Set<String>()
        for group in ModuleGroup.allCases {
            for m in registry.modules(in: group) {
                XCTAssertFalse(seen.contains(m.id), "\(m.id) duplicated across tabs")
                seen.insert(m.id)
            }
        }
    }

    func testHomeDefaultPlacementsMatchHomeGroup() {
        let (registry, settings) = makeRegistry()
        let dashboard = DashboardModel(settings: settings, registry: registry)
        let placedIDs = Set(dashboard.placements(for: .regular).map(\.moduleID))
        XCTAssertEqual(placedIDs, Set(registry.modules(in: .home).map(\.id)))
    }
}

@MainActor
final class NoteAndMirrorDefaultsTests: XCTestCase {
    func testNoteLocalPersistence() {
        let name = "note-\(UUID().uuidString).json"
        let s1 = QuickNoteService(fileName: name)
        s1.text = "buy milk"
        // Persist is debounced; force immediate reload via a new instance after save.
        let exp = expectation(description: "persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        let s2 = QuickNoteService(fileName: name)
        XCTAssertEqual(s2.text, "buy milk")
    }

    func testNoteDefaultColorIsYellow() {
        XCTAssertEqual(AppSettings().noteColor, .yellow)
    }

    func testMirrorDefaultCircular() {
        XCTAssertTrue(AppSettings().mirrorCircular)
        XCTAssertTrue(AppSettings().mirrorZoomed)
    }

    func testBackgroundIntensityPersistsDeepBlackDefault() {
        XCTAssertEqual(AppSettings().backgroundIntensity, .deepBlack)
        let settings = SettingsStore.inMemory()
        settings.settings.backgroundIntensity = .maxContrast
        settings.saveNow()
        XCTAssertEqual(settings.settings.backgroundIntensity, .maxContrast)
    }
}

final class ResponsiveWideningTests: XCTestCase {
    func testUtilitiesWiderButClamped() {
        let geo = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 940),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 910),
                                 notchWidth: 200, notchHeight: 32, backingScaleFactor: 2)
        let util = NotchResponsiveLayoutService.compute(screen: geo, face: .utilities,
                    prefs: .init(), accessibility: .init())
        let agents = NotchResponsiveLayoutService.compute(screen: geo, face: .agents,
                    prefs: .init(), accessibility: .init())
        XCTAssertGreaterThan(util.panelWidth, agents.panelWidth)          // utilities wider
        XCTAssertLessThanOrEqual(util.panelWidth, NotchResponsiveLayoutService.hardMaxWidth)
        XCTAssertLessThanOrEqual(util.panelWidth, 1512 - 48)              // safe margins
    }
}

final class PomodoroCycleTests: XCTestCase {
    func testFreshCycleEmpty() {
        let c = PomodoroCycle.compute(completedWorkSessions: 0, sessionsBeforeLongBreak: 4, phase: .work)
        XCTAssertEqual(c.filledSlices, 0); XCTAssertEqual(c.totalSlices, 4)
        XCTAssertFalse(c.isBreak)
    }
    func testMidCycle() {
        let c = PomodoroCycle.compute(completedWorkSessions: 2, sessionsBeforeLongBreak: 4, phase: .shortBreak)
        XCTAssertEqual(c.filledSlices, 2)
        XCTAssertTrue(c.isBreak)
        XCTAssertFalse(c.isLongBreak)
    }
    func testLongBreakFillsAll() {
        let c = PomodoroCycle.compute(completedWorkSessions: 4, sessionsBeforeLongBreak: 4, phase: .longBreak)
        XCTAssertEqual(c.filledSlices, 4)
        XCTAssertTrue(c.isLongBreak)
    }
    func testWrapsAfterLongBreak() {
        let c = PomodoroCycle.compute(completedWorkSessions: 4, sessionsBeforeLongBreak: 4, phase: .work)
        XCTAssertEqual(c.filledSlices, 0)   // new cycle
    }
}

import XCTest
@testable import NotchDeck

@MainActor
final class PinIsolationTests: XCTestCase {
    private func makeState() -> AppState { AppState(settings: SettingsStore.inMemory()) }

    func testStartingPomodoroDoesNotPin() {
        let state = makeState()
        let pomodoro = PomodoroService(config: PomodoroConfig(),
                                       notifications: MockNotificationService(),
                                       fileName: "pin-\(UUID().uuidString).json")
        pomodoro.start()
        XCTAssertTrue(pomodoro.engine.isRunning)
        XCTAssertFalse(state.isPinnedByUser)   // timer must never pin
    }

    func testEnablingMirrorDoesNotPin() {
        let state = makeState()
        let mirror = MirrorService(permission: MockCameraPermissionService(_status: .granted, requestResult: .granted))
        mirror.toggle()
        XCTAssertTrue(mirror.isEnabled)
        XCTAssertFalse(state.isPinnedByUser)
    }

    func testExpandAndFaceSwitchDoNotPin() {
        let state = makeState()
        state.expand()
        state.toggleFace(to: .agents)
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.isPinnedByUser)
    }

    func testOnlyExplicitCallTogglesPin() {
        let state = makeState()
        XCTAssertFalse(state.isPinnedByUser)
        state.setPinnedByUser(true, reason: "pin button")
        XCTAssertTrue(state.isPinnedByUser)
        state.setPinnedByUser(false, reason: "escape")
        XCTAssertFalse(state.isPinnedByUser)
    }

    func testShouldStayOpenReflectsTransientFlagsOnly() {
        let state = makeState()
        XCTAssertFalse(state.shouldStayOpen)          // nothing → collapses
        state.isPointerInside = true
        XCTAssertTrue(state.shouldStayOpen)
        state.isPointerInside = false
        state.isEditing = true
        XCTAssertTrue(state.shouldStayOpen)
        state.isEditing = false
        state.isSecondaryWindowOpen = true
        XCTAssertTrue(state.shouldStayOpen)
        state.isSecondaryWindowOpen = false
        XCTAssertFalse(state.shouldStayOpen)           // a running Pomodoro is not represented here → never keeps open
    }

    func testSettingsFlowUnpins() {
        let state = makeState()
        state.setPinnedByUser(true, reason: "pin button")
        // Mimic prepareForSecondaryWindow's pin-clearing contract.
        state.isSecondaryWindowOpen = true
        state.setPinnedByUser(false, reason: "secondary window opened")
        XCTAssertFalse(state.isPinnedByUser)
    }
}

@MainActor
final class CompactPomodoroTests: XCTestCase {
    func testCountdownContinuesRegardlessOfPanel() {
        let service = PomodoroService(config: PomodoroConfig(workMinutes: 25),
                                      notifications: MockNotificationService(),
                                      fileName: "compact-\(UUID().uuidString).json")
        service.start()
        // Engine is the source of truth; collapsing the panel doesn't touch it.
        XCTAssertTrue(service.engine.isRunning)
        XCTAssertGreaterThan(service.remaining, 0)
        // Formatted MM:SS shape for the compact live activity.
        XCTAssertEqual(service.formattedRemaining.count, 5)
        XCTAssertTrue(service.formattedRemaining.contains(":"))
    }

    func testStopHidesLiveActivity() {
        let service = PomodoroService(config: PomodoroConfig(),
                                      notifications: MockNotificationService(),
                                      fileName: "compact-\(UUID().uuidString).json")
        service.start()
        XCTAssertTrue(service.engine.isRunning)
        service.reset()
        XCTAssertFalse(service.engine.isRunning)   // live activity disappears
    }
}

final class HookDiagnosticsTests: XCTestCase {
    func testValidationReportsSocketState() {
        let offline = HookInstaller.validate(.codex, socketExists: false)
        XCTAssertTrue(offline.contains { $0.name == "Bridge socket" && !$0.ok })
        let online = HookInstaller.validate(.codex, socketExists: true)
        XCTAssertTrue(online.contains { $0.name == "Bridge socket" && $0.ok })
    }

    func testValidationCoversAllChecks() {
        let checks = HookInstaller.validate(.claudeCode, socketExists: false).map(\.name)
        XCTAssertTrue(checks.contains("Config file"))
        XCTAssertTrue(checks.contains("Hooks installed"))
        XCTAssertTrue(checks.contains("Helper installed"))
        XCTAssertTrue(checks.contains("Bridge socket"))
    }

    func testDiagnosticReportIsSanitizedText() {
        let report = HookInstaller.diagnosticReport(.codex, socketExists: false)
        XCTAssertTrue(report.contains("terminal integration"))
        XCTAssertTrue(report.contains("codex"))
        XCTAssertFalse(report.contains(NSHomeDirectory()))   // home collapsed to ~
    }

    func testInstalledHelperPathIsInApplicationSupport() {
        let path = HookInstaller.installedHelperURL.path
        XCTAssertTrue(path.hasSuffix("notchdeck-agent-hook"))
        XCTAssertTrue(path.contains("NotchDeck"))
    }
}

@MainActor
final class ConnectedSessionPersistenceTests: XCTestCase {
    func testExternalScanDoesNotWipeConnectedSession() {
        let store = AgentSessionStore(fileName: "conn-\(UUID().uuidString).json")
        var connected = AgentSession(provider: .claudeCode, title: "live", projectPath: "/tmp",
                                     status: .running, isManaged: false)
        connected.isBridgeConnected = true
        store.upsert(connected)

        // A fresh Accessibility scan (which yields only plain external windows)
        // must NOT remove the hook-connected session.
        store.replaceExternal([])
        XCTAssertTrue(store.sessions.contains { $0.id == connected.id && $0.isBridgeConnected })
    }

    func testImmediateSessionStartInsertion() {
        // The bridge reducer produces a Connected/running session from a single
        // SessionStart event — no waiting on the external scan.
        let s = TerminalAgentBridge.reduce(
            existing: nil, id: UUID(),
            event: TerminalAgentEvent(type: .sessionStarted, provider: .claudeCode,
                                      sessionID: "x", cwd: "/tmp/proj", timestamp: 1))
        XCTAssertEqual(s.connectivity, .connected)
        XCTAssertEqual(s.status, .running)
    }
}

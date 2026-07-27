import XCTest
@testable import NotchDeck

final class PointerTrackingServiceTests: XCTestCase {
    let compact = CGRect(x: 100, y: 900, width: 200, height: 48)
    let expanded = CGRect(x: 60, y: 620, width: 720, height: 320)

    func testInsideCompact() {
        let s = PointerTrackingService.evaluate(location: CGPoint(x: 150, y: 920),
                                                compact: compact, expanded: expanded)
        XCTAssertTrue(s.insideCompactActivation)
        XCTAssertTrue(s.insideAny)
    }

    func testInsideExpanded() {
        let s = PointerTrackingService.evaluate(location: CGPoint(x: 400, y: 700),
                                                compact: compact, expanded: expanded)
        XCTAssertTrue(s.insideExpandedPanel)
        XCTAssertTrue(s.insideAny)
    }

    func testOutsideBoth() {
        let s = PointerTrackingService.evaluate(location: CGPoint(x: 10, y: 10),
                                                compact: compact, expanded: expanded)
        XCTAssertFalse(s.insideAny)
    }
}

final class TerminalProtocolTests: XCTestCase {
    func testProtocolVersion() {
        XCTAssertEqual(TerminalAgentProtocol.version, 1)
    }

    func testSocketPathUnderApplicationSupport() {
        let path = TerminalAgentProtocol.socketURL().path
        XCTAssertTrue(path.contains("NotchDeck"))
        XCTAssertTrue(path.hasSuffix(".sock"))
        XCTAssertTrue(path.contains("Application Support") || path.contains("/tmp"))
    }

    func testEventCodecRoundTrip() throws {
        let event = TerminalAgentEvent(type: .toolPermissionRequested, provider: .claudeCode,
                                       sessionID: "s1", cwd: "/tmp/p", timestamp: 123,
                                       toolName: "Bash", summary: "ls", requestID: "r1")
        let line = TerminalAgentCodec.encodeLine(event)!
        let str = String(data: line, encoding: .utf8)!.trimmingCharacters(in: .newlines)
        let decoded = TerminalAgentCodec.decodeEvent(str)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded?.protocolVersion, 1)
    }

    func testDecisionCodecRoundTrip() throws {
        let d = TerminalAgentDecision(requestID: "r1", behavior: .allow, message: "ok")
        let line = TerminalAgentCodec.encodeLine(d)!
        let str = String(data: line, encoding: .utf8)!.trimmingCharacters(in: .newlines)
        XCTAssertEqual(TerminalAgentCodec.decodeDecision(str), d)
    }

    func testTrailingNewlineFraming() {
        let event = TerminalAgentEvent(type: .heartbeat, provider: .codex, sessionID: "s", timestamp: 1)
        let line = TerminalAgentCodec.encodeLine(event)!
        XCTAssertEqual(line.last, 0x0A)
    }
}

final class TerminalBridgeReduceTests: XCTestCase {
    private func event(_ type: TerminalAgentEventType, requestID: String? = nil) -> TerminalAgentEvent {
        TerminalAgentEvent(type: type, provider: .codex, sessionID: "sess", cwd: "/tmp/proj",
                           timestamp: 100, toolName: "shell", summary: "rm -rf x", requestID: requestID)
    }
    private let id = UUID()

    func testSessionStartedConnectsRunning() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: id, event: event(.sessionStarted))
        XCTAssertTrue(s.isBridgeConnected)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(s.connectivity, .connected)
        XCTAssertEqual(s.projectPath, "/tmp/proj")
    }

    func testPermissionRequestedNeedsApproval() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: id, event: event(.toolPermissionRequested, requestID: "r9"))
        XCTAssertEqual(s.status, .waitingForApproval)
        XCTAssertTrue(s.requiresAttention)
        XCTAssertEqual(s.pendingApprovalRequestID, "r9")
    }

    func testSessionEndedDisconnects() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: id, event: event(.sessionStarted))
        s = TerminalAgentBridge.reduce(existing: s, id: id, event: event(.sessionEnded))
        XCTAssertFalse(s.isBridgeConnected)
        XCTAssertEqual(s.status, .completed)
    }
}

final class HookInstallerTests: XCTestCase {

    func testClaudeMergeAddsMarkedHooks() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/bin/notchdeck-agent-hook")
        XCTAssertTrue(HookInstaller.hasMarker(in: merged, provider: .claudeCode))
        // Claude nests under "hooks".
        XCTAssertNotNil(merged["hooks"])
    }

    func testCodexMergeIsTopLevel() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .codex, helper: "/tmp/bin/notchdeck-agent-hook")
        XCTAssertTrue(HookInstaller.hasMarker(in: merged, provider: .codex))
        XCTAssertNotNil(merged["PermissionRequest"])
        XCTAssertNil(merged["hooks"])   // codex is not nested
    }

    func testMergePreservesUserHooks() {
        let base: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "Bash",
            "hooks": [["type": "command", "command": "/usr/bin/mytool"]]]]]]
        let merged = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/tmp/bin/notchdeck-agent-hook")
        let hooks = merged["hooks"] as! [String: Any]
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        // User entry retained + NotchDeck entry added.
        XCTAssertTrue(pre.contains { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/usr/bin/mytool" } ?? false
        })
        XCTAssertGreaterThanOrEqual(pre.count, 2)
    }

    func testMergeIsIdempotent() {
        let once = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/bin/notchdeck-agent-hook")
        let twice = HookInstaller.mergeHooks(base: once, provider: .claudeCode, helper: "/tmp/bin/notchdeck-agent-hook")
        let hooks = twice["hooks"] as! [String: Any]
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        // Only one NotchDeck entry for the event even after merging twice.
        let notchEntries = pre.filter { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("notchdeck-agent-hook") ?? false } ?? false
        }
        XCTAssertEqual(notchEntries.count, 1)
    }

    func testUninstallRemovesOnlyOurs() {
        let base: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "Bash",
            "hooks": [["type": "command", "command": "/usr/bin/mytool"]]]]]]
        let merged = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/tmp/bin/notchdeck-agent-hook")
        let cleaned = HookInstaller.removeHooks(base: merged, provider: .claudeCode)
        XCTAssertFalse(HookInstaller.hasMarker(in: cleaned, provider: .claudeCode))
        // User hook survives.
        let hooks = cleaned["hooks"] as! [String: Any]
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertTrue(pre.contains { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/usr/bin/mytool" } ?? false
        })
    }
}

@MainActor
final class MirrorAndPomodoroServiceTests: XCTestCase {

    func testMirrorToggleFlipsEnabled() {
        let service = MirrorService(permission: MockCameraPermissionService(_status: .granted, requestResult: .granted))
        XCTAssertFalse(service.isEnabled)
        service.toggle()
        XCTAssertTrue(service.isEnabled)
        service.toggle()
        XCTAssertFalse(service.isEnabled)
    }

    func testPomodoroRunsIndependentlyAndStopsOnQuit() {
        let name = "pomo-\(UUID().uuidString).json"
        let service = PomodoroService(config: PomodoroConfig(),
                                      notifications: MockNotificationService(),
                                      fileName: name)
        service.start()
        XCTAssertTrue(service.engine.isRunning)
        XCTAssertGreaterThan(service.remaining, 0)
        // Quit must stop the active timer but preserve stats.
        service.resetActiveStateForQuit()
        XCTAssertFalse(service.engine.isRunning)
        XCTAssertEqual(service.engine.phase, .idle)
    }
}

final class AgentConnectivityTests: XCTestCase {
    func testConnectivityClassification() {
        let managed = AgentSession(provider: .codex, title: "m", projectPath: "/p", isManaged: true)
        XCTAssertEqual(managed.connectivity, .connected)

        var bridged = AgentSession(provider: .codex, title: "b", projectPath: "/p", isManaged: false)
        bridged.isBridgeConnected = true
        XCTAssertEqual(bridged.connectivity, .connected)

        let external = AgentSession(provider: .external, title: "e", projectPath: "",
                                    status: .unavailable, isManaged: false,
                                    externalBundleID: "com.apple.Terminal")
        XCTAssertEqual(external.connectivity, .external)
    }
}

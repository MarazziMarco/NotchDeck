import XCTest
@testable import NotchDeck

// MARK: Terminal focus (existing tab, never a new window)

final class TerminalFocusTests: XCTestCase {
    func testNormalizeTTY() {
        XCTAssertEqual(TerminalFocus.normalizeTTY("ttys003"), "/dev/ttys003")
        XCTAssertEqual(TerminalFocus.normalizeTTY("/dev/ttys007"), "/dev/ttys007")
        XCTAssertEqual(TerminalFocus.normalizeTTY("  ttys012 \n"), "/dev/ttys012")
    }
    func testParseTTYList() {
        let out = "/dev/ttys001,/dev/ttys002,ttys003,,junk\n"
        let set = TerminalFocus.parseTTYList(out)
        XCTAssertEqual(set, ["/dev/ttys001", "/dev/ttys002", "/dev/ttys003"])
    }
    func testFocusScriptTargetsExactTTY() {
        let s = TerminalFocus.focusTTYScript(tty: "ttys009")
        XCTAssertTrue(s.contains("/dev/ttys009"))
        XCTAssertTrue(s.contains("set selected of t to true"))
        XCTAssertTrue(s.contains("miniaturized"))
    }
    func testFocusScriptNeverSpawnsOrRuns() {
        let s = TerminalFocus.focusTTYScript(tty: "ttys001")
        XCTAssertTrue(TerminalFocus.isSafeFocusScript(s))
        XCTAssertFalse(s.lowercased().contains("do script"))
        XCTAssertFalse(s.lowercased().contains("open -a"))
    }
    func testEnumerateScriptIsReadOnly() {
        let s = TerminalFocus.enumerateTTYsScript()
        XCTAssertTrue(TerminalFocus.isSafeFocusScript(s))
        XCTAssertTrue(s.contains("tty of t"))
        XCTAssertFalse(s.contains("do script"))
    }
    func testUnavailableMessage() {
        XCTAssertEqual(TerminalFocus.unavailableMessage,
                       "The original terminal session is no longer available")
    }
    func testSafetyAuditRejectsDoScript() {
        XCTAssertFalse(TerminalFocus.isSafeFocusScript("tell app \"Terminal\" to do script \"ls\""))
    }
}

// MARK: Focus feedback messages (reason-accurate, no false "unavailable")

final class TerminalFocusFeedbackTests: XCTestCase {
    func testFoundHasNoMessage() {
        XCTAssertNil(TerminalFocusFeedback.message(for: .found(.init(tty: "/dev/ttys003")), presence: .present))
    }
    func testUnknownNeverShowsUnavailable() {
        // A query error with presence still unknown must NOT read as "gone".
        let msg = TerminalFocusFeedback.message(for: .enumerationFailed("x"), presence: .unknown)
        XCTAssertEqual(msg, TerminalFocusFeedback.verifyFailed)
        XCTAssertNotEqual(msg, TerminalFocusFeedback.unavailable)
    }
    func testPermissionDeniedMessage() {
        XCTAssertEqual(TerminalFocusFeedback.message(for: .automationPermissionDenied, presence: .unknown),
                       "NotchDeck does not have permission to control Terminal")
    }
    func testMissingTTYMessage() {
        XCTAssertEqual(TerminalFocusFeedback.message(for: .missingSessionTTY, presence: .unknown),
                       "This session has not yet been linked to its Terminal tab")
    }
    func testTerminalNotRunningIsUnavailable() {
        XCTAssertEqual(TerminalFocusFeedback.message(for: .terminalNotRunning, presence: .unknown),
                       TerminalFocus.unavailableMessage)
    }
    func testTtyNotFoundTransientWhenNotConfirmed() {
        // Tab not matched this pass but not yet confirmed-missing → transient, not "gone".
        XCTAssertEqual(TerminalFocusFeedback.message(for: .ttyNotFound, presence: .present),
                       TerminalFocusFeedback.temporary)
        XCTAssertEqual(TerminalFocusFeedback.message(for: .ttyNotFound, presence: .unknown),
                       TerminalFocusFeedback.temporary)
    }
    func testTtyNotFoundUnavailableOnlyWhenMissing() {
        XCTAssertEqual(TerminalFocusFeedback.message(for: .ttyNotFound, presence: .missing),
                       TerminalFocus.unavailableMessage)
    }
    func testUnavailableMessageNeverShownForUnknownReasons() {
        for r: TerminalSessionLookupResult in [.automationPermissionDenied, .missingSessionTTY,
                                               .enumerationFailed("t"), .unsupportedTerminal("iTerm")] {
            XCTAssertNotEqual(TerminalFocusFeedback.message(for: r, presence: .unknown),
                              TerminalFocus.unavailableMessage)
        }
    }
}

// MARK: Terminal presence vs activity

final class TerminalPresenceTests: XCTestCase {
    func testTerminalQuitMakesMissing() {
        XCTAssertEqual(AgentTerminalPresence.evaluate(terminalAppRunning: false, ttyKnown: true, ttyActive: true),
                       .missing)
    }
    func testTabOpenIsPresent() {
        XCTAssertEqual(AgentTerminalPresence.evaluate(terminalAppRunning: true, ttyKnown: true, ttyActive: true),
                       .present)
    }
    func testTabClosedIsMissing() {
        XCTAssertEqual(AgentTerminalPresence.evaluate(terminalAppRunning: true, ttyKnown: true, ttyActive: false),
                       .missing)
    }
    func testNoTTYIsUnknown() {
        XCTAssertEqual(AgentTerminalPresence.evaluate(terminalAppRunning: true, ttyKnown: false, ttyActive: nil),
                       .unknown)
    }
    func testActivityStateSeparateFromLifecycle() {
        XCTAssertEqual(AgentActivityState.from(.completed), .completed)
        XCTAssertEqual(AgentActivityState.from(.idle), .idle)
        XCTAssertEqual(AgentActivityState.from(.waitingForApproval), .waitingForApproval)
        XCTAssertEqual(AgentActivityState.from(.running), .running)
    }
    func testIdleNoEventsButTabOpenIsActive() {
        // "No hook event for ten minutes, terminal still open → Active."
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .present, status: .idle,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .active)
    }
    func testStopReceivedTabOpenIsActive() {
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .present, status: .completed,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .active)
    }

    // MARK: Debounce (3 confirmed misses)

    private func run(_ obs: [TerminalObservation],
                     from start: TerminalPresenceDebounce.State =
                        .init(presence: .present, missCount: 0)) -> TerminalPresenceDebounce.State {
        obs.reduce(start) { TerminalPresenceDebounce.step($0, $1) }
    }

    func testThresholdIsThree() {
        XCTAssertEqual(TerminalPresenceDebounce.missThreshold, 3)
    }
    func testOneConfirmedMissStaysActive() {
        let s = run([.absent])
        XCTAssertEqual(s.presence, .present)   // still Active
        XCTAssertEqual(s.missCount, 1)
    }
    func testTwoConfirmedMissesStayActive() {
        let s = run([.absent, .absent])
        XCTAssertEqual(s.presence, .present)
        XCTAssertEqual(s.missCount, 2)
    }
    func testThirdConfirmedMissMovesToMissing() {
        let s = run([.absent, .absent, .absent])
        XCTAssertEqual(s.presence, .missing)   // → Recent
        XCTAssertEqual(s.missCount, 3)
    }
    func testQueryErrorDoesNotIncrementCounter() {
        // miss, ERROR, miss → only two confirmed misses, still Active.
        let s = run([.absent, .queryError, .absent])
        XCTAssertEqual(s.missCount, 2)
        XCTAssertEqual(s.presence, .present)
    }
    func testTTYReappearingResetsCounter() {
        let s = run([.absent, .absent, .present])
        XCTAssertEqual(s.missCount, 0)
        XCTAssertEqual(s.presence, .present)
        // and a following single miss is only 1 again
        XCTAssertEqual(run([.absent], from: s).missCount, 1)
    }
    func testAppTerminationMarksMissingImmediately() {
        let s = run([.appTerminated])
        XCTAssertEqual(s.presence, .missing)
        XCTAssertEqual(s.missCount, TerminalPresenceDebounce.missThreshold)
    }
    func testErrorAloneStaysActiveUnknown() {
        let s = run([.queryError])
        XCTAssertEqual(s.presence, .unknown)   // unknown → Active for connected
        XCTAssertEqual(s.missCount, 0)
    }

    @MainActor func testStorePresenceTransitionMovesBuckets() {
        let store = AgentSessionStore(fileName: "presence-\(UUID()).json")
        var s = AgentSession(provider: .claudeCode, title: "t", projectPath: "/p",
                             status: .completed, isManaged: false)
        s.isBridgeConnected = true
        s.terminalTTY = "/dev/ttys050"
        s.terminalPresence = .present
        store.upsert(s)
        XCTAssertEqual(store.activeSessions.count, 1)   // tab open → Active even though completed

        store.update(id: s.id) { $0.terminalPresence = .missing }   // tab closed
        XCTAssertTrue(store.activeSessions.isEmpty)
        XCTAssertEqual(store.recentSessions.count, 1)   // now Recent
    }
}

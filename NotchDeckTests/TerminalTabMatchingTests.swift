import XCTest
@testable import NotchDeck

/// Focus Terminal + presence: canonical TTY, exact matching, full enumeration,
/// safe actuation, and truthful error states — all via fakes (no real Terminal).
final class TerminalTabMatchingTests: XCTestCase {

    private func tab(_ w: Int, _ t: Int, _ tty: String, selected: Bool = false, min: Bool = false) -> TerminalTabDescriptor {
        TerminalTabDescriptor(windowIndex: w, tabIndex: t, tty: tty, selected: selected, minimized: min)
    }

    private func session(tty: String?, app: String = "Terminal",
                         bundle: String? = "com.apple.Terminal") -> AgentSession {
        var s = AgentSession(provider: .claudeCode, title: "p", projectPath: "/tmp",
                             status: .running, isManaged: false)
        s.terminalTTY = tty
        s.terminalAppName = app
        s.terminalBundleID = bundle
        s.isBridgeConnected = true
        return s
    }

    // MARK: Canonicalisation + exact match (tests 25, 26)

    func testCanonicalisesShortTTY() {
        XCTAssertEqual(TerminalTabMatching.canonical("ttys003"), "/dev/ttys003")
        XCTAssertEqual(TerminalTabMatching.canonical("/dev/ttys003"), "/dev/ttys003")
    }

    func testExactMatchNoPrefixConfusion() {
        let tabs = [tab(1, 1, "/dev/ttys01"), tab(1, 2, "/dev/ttys010")]
        XCTAssertEqual(TerminalTabMatching.match(tty: "/dev/ttys010", in: tabs)?.tabIndex, 2)
        XCTAssertEqual(TerminalTabMatching.match(tty: "ttys01", in: tabs)?.tabIndex, 1)
        XCTAssertNil(TerminalTabMatching.match(tty: "/dev/ttys0", in: tabs), "no substring/prefix match")
    }

    // MARK: Enumeration parse (tests 27–31)

    func testParsesAllWindowsAndTabs() {
        let out = """
        1|1|/dev/ttys001|true|false
        1|2|/dev/ttys002|false|false
        2|1|/dev/ttys003|false|true
        """
        let tabs = TerminalTabInventory.parse(out)
        XCTAssertEqual(tabs.count, 3)
        XCTAssertEqual(Set(tabs.map(\.windowIndex)), [1, 2])
        XCTAssertEqual(TerminalTabMatching.match(tty: "ttys003", in: tabs)?.windowIndex, 2, "background-window tab found")
        XCTAssertTrue(TerminalTabMatching.match(tty: "ttys003", in: tabs)?.minimized ?? false)
    }

    func testMatchInSecondWindowBackgroundTab() {
        let tabs = [tab(1, 1, "/dev/ttys001", selected: true), tab(2, 3, "/dev/ttys009")]
        XCTAssertEqual(TerminalTabMatching.match(tty: "/dev/ttys009", in: tabs)?.windowIndex, 2)
    }

    // MARK: Script safety (tests 32–35)

    func testFocusScriptSelectsWithoutRunningCommands() {
        let s = TerminalFocus.focusTTYScript(tty: "ttys003")
        XCTAssertTrue(s.contains("selected of t"))
        XCTAssertTrue(s.contains("miniaturized of w"), "un-minimises the containing window")
        XCTAssertTrue(TerminalFocus.isSafeFocusScript(s))
        XCTAssertFalse(s.lowercased().contains("do script"))
        XCTAssertFalse(s.lowercased().contains("make new"))
        XCTAssertFalse(s.lowercased().contains("clipboard"))
    }

    func testInventoryScriptIsReadOnlyAndEnumeratesEverything() {
        let s = TerminalTabInventory.script()
        XCTAssertTrue(s.contains("repeat with w in windows"))
        XCTAssertTrue(s.contains("tabs of w"))
        XCTAssertTrue(TerminalTabInventory.isReadOnlyScript(s))
        XCTAssertFalse(s.lowercased().contains("do script"))
    }

    // MARK: Same-directory sessions distinguished by TTY (test 37)

    func testSameDirectoryDistinguishedByTTY() {
        let tabs = [tab(1, 1, "/dev/ttys001"), tab(1, 2, "/dev/ttys002")]
        let a = session(tty: "/dev/ttys001"); let b = session(tty: "/dev/ttys002")
        XCTAssertEqual(TerminalTabMatching.match(tty: a.terminalTTY!, in: tabs)?.tabIndex, 1)
        XCTAssertEqual(TerminalTabMatching.match(tty: b.terminalTTY!, in: tabs)?.tabIndex, 2)
    }

    // MARK: Presence uses the same matcher (test 38)

    func testPresenceObservationUsesCanonicalMatcher() {
        let ctl = TerminalController()
        let present = ctl.observation(for: session(tty: "ttys003"),
                                      result: .success(["/dev/ttys003"]))
        XCTAssertEqual(present, .present)
        let absent = ctl.observation(for: session(tty: "ttys004"),
                                     result: .success(["/dev/ttys003"]))
        XCTAssertEqual(absent, .absent)
    }

    // MARK: Definitive no-match vs query failure (tests 39, 40, 44)

    func testQueryErrorIsNotAMiss() {
        let ctl = TerminalController()
        XCTAssertEqual(ctl.observation(for: session(tty: "ttys003"), result: .queryError), .queryError)
    }

    func testAppTerminatedIsMissImmediately() {
        let ctl = TerminalController()
        XCTAssertEqual(ctl.observation(for: session(tty: "ttys003"), result: .terminalNotRunning), .appTerminated)
    }

    func testQueryErrorDoesNotDemoteToRecent() {
        // A single query error must not flip a present session to missing.
        let prev = TerminalPresenceDebounce.State(presence: .present, missCount: 0)
        let next = TerminalPresenceDebounce.step(prev, .queryError)
        XCTAssertNotEqual(next.presence, .missing)
    }

    // MARK: Truthful feedback states (test 16, 41, 43)

    func testFeedbackDistinguishesFailureModes() {
        XCTAssertEqual(TerminalFocusFeedback.message(for: .automationPermissionDenied, presence: .present),
                       TerminalFocusFeedback.permissionDenied)
        XCTAssertEqual(TerminalFocusFeedback.message(for: .missingSessionTTY, presence: .present),
                       TerminalFocusFeedback.notLinked)
        XCTAssertEqual(TerminalFocusFeedback.message(for: .unsupportedTerminal("iTerm"), presence: .present),
                       TerminalFocusFeedback.unsupported)
        // A transient no-match on a still-present session is NOT "gone".
        XCTAssertEqual(TerminalFocusFeedback.message(for: .ttyNotFound, presence: .present),
                       TerminalFocusFeedback.temporary)
        XCTAssertEqual(TerminalFocusFeedback.message(for: .found(.init(tty: "/dev/ttys1")), presence: .present), nil)
    }

    // MARK: Unsupported terminal / missing TTY early returns (tests 41, 43)

    func testUnsupportedTerminalDoesNotDriveTerminalApp() {
        let ctl = TerminalController()
        let s = session(tty: "/dev/ttys003", app: "iTerm2", bundle: "com.googlecode.iterm2")
        XCTAssertEqual(ctl.lookup(session: s), .unsupportedTerminal("iTerm2"))
    }

    func testMissingTTYReportedTruthfully() {
        let ctl = TerminalController()
        XCTAssertEqual(ctl.lookup(session: session(tty: nil)), .missingSessionTTY)
    }
}

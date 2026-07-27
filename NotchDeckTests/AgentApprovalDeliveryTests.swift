import XCTest
@testable import NotchDeck

/// Approval delivery re-architected onto the PreToolUse decision hook. Truthful
/// states: socket write / responseWritten is NOT provider acceptance.
final class AgentApprovalDeliveryTests: XCTestCase {

    /// A PreToolUse decision event (the authoritative approval-creating channel),
    /// correlated by tool-use id.
    private func decisionEvent(requestID: String, toolUseID: String? = nil,
                               provider: TerminalAgentProvider = .claudeCode,
                               tty: String? = nil) -> TerminalAgentEvent {
        TerminalAgentEvent(type: .toolPermissionRequested, provider: provider, sessionID: "s",
                           cwd: "/tmp", timestamp: 0, toolName: "Bash", tty: tty,
                           requestID: requestID, toolUseID: toolUseID ?? requestID)
    }

    // MARK: Exact provider response schema — PreToolUse (verified live)

    func testClaudeAllowSchemaIsPreToolUse() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}"#)
    }

    func testClaudeDenySchemaIsPreToolUse() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .deny, message: "Denied in NotchDeck"),
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied in NotchDeck"}}"#)
    }

    func testCodexAllowSchemaIsPreToolUse() {
        XCTAssertEqual(PermissionResponse.json(provider: .codex, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}"#)
    }

    func testDecisionHookEventIsPreToolUse() {
        XCTAssertEqual(PermissionResponse.decisionHookEvent, "PreToolUse")
    }

    func testResponseIsNotTheDecisionBehaviorShape() {
        let s = PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil)
        XCTAssertFalse(s.contains(#""decision":{"#))
        XCTAssertFalse(s.contains("behavior"))
    }

    func testStdoutLineSingleNewlineNoDiagnostics() {
        let line = PermissionResponse.stdoutLine(provider: .claudeCode, behavior: .allow, message: nil)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertFalse(line.lowercased().contains("provider="))
        XCTAssertFalse(line.lowercased().contains("socket"))
    }

    func testUnknownProviderMinimalSchema() {
        XCTAssertEqual(PermissionResponse.json(provider: .unknown, behavior: .deny, message: nil),
                       #"{"permissionDecision":"deny"}"#)
    }

    // MARK: Approval creation / correlation / observer

    func testPreToolUseCreatesApprovalWithCorrelationID() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: decisionEvent(requestID: "tuse_1"))
        XCTAssertEqual(s.approval?.requestID, "tuse_1")
        XCTAssertEqual(s.approval?.rawEventName, "PreToolUse")
        XCTAssertEqual(s.approval?.state, .pending)
    }

    func testPermissionRequestIsObserverAndNeverCreatesApproval() {
        XCTAssertFalse(ApprovalClassifier.createsApproval(.permissionRequested))
        XCTAssertTrue(ApprovalClassifier.createsApproval(.toolPermissionRequested))
        let e = TerminalAgentEvent(type: .permissionRequested, provider: .claudeCode,
                                   sessionID: "s", timestamp: 0, requestID: "r")
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e)
        XCTAssertNil(s.approval, "PermissionRequest must never create an approval")
    }

    func testToolStartedNeverCreatesApproval() {
        let e = TerminalAgentEvent(type: .toolStarted, provider: .claudeCode, sessionID: "s",
                                   timestamp: 0, toolName: "Bash")
        XCTAssertNil(TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e).approval)
    }

    func testDuplicatePreToolUseDoesNotDuplicateApproval() {
        let id = UUID()
        let first = TerminalAgentBridge.reduce(existing: nil, id: id, event: decisionEvent(requestID: "r1"))
        let again = TerminalAgentBridge.reduce(existing: first, id: id, event: decisionEvent(requestID: "r1"))
        XCTAssertEqual(again.approval?.state, .pending, "idempotent — no second approval")
    }

    // MARK: Truthful states — socket write is NOT acceptance

    func testResponseWrittenShowsSentNotApproved() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: decisionEvent(requestID: "r"))
        s.approval?.state = .sending
        s.approval?.decidedAllow = true
        TerminalAgentBridge.applyResponseWritten(&s)
        XCTAssertEqual(s.approval?.state, .sent)
        XCTAssertEqual(s.latestSummary, "Sent to Claude")
        XCTAssertNotEqual(s.latestSummary, "Approved", "never Approved on a mere write")
        XCTAssertNotNil(s.approval, "kept as a non-interactive Sent… state")
        XCTAssertFalse(s.approval!.isLive, "not clickable once sent")
    }

    func testClaudeContinuedOnlyOnProviderProgression() {
        // sent → PostToolUse for the SAME tool-use id proves the CLI continued.
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: decisionEvent(requestID: "tuse_9"))
        s.approval?.state = .sent
        s.approval?.decidedAllow = true
        let done = TerminalAgentBridge.reduce(existing: s, id: s.id,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .claudeCode, sessionID: "s",
                                      timestamp: 1, toolUseID: "tuse_9"))
        XCTAssertEqual(done.latestSummary, "Claude continued")
        XCTAssertNil(done.approval, "cleared after progression")
    }

    func testLateResponseWrittenIsNoOp() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: decisionEvent(requestID: "r"))
        s.approval = nil
        s.latestSummary = "was-terminal"
        TerminalAgentBridge.applyResponseWritten(&s)
        XCTAssertEqual(s.latestSummary, "was-terminal")
    }

    // MARK: TTY capture/preserve

    func testTTYCanonicalisedOnStore() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: decisionEvent(requestID: "r", tty: "ttys003"))
        XCTAssertEqual(s.terminalTTY, "/dev/ttys003")
    }

    func testStoredTTYNotOverwrittenByNil() {
        var first = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                               event: decisionEvent(requestID: "r", tty: "/dev/ttys005"))
        first = TerminalAgentBridge.reduce(existing: first, id: first.id,
                                           event: TerminalAgentEvent(type: .toolStarted, provider: .claudeCode,
                                                                     sessionID: "s", timestamp: 1, tty: nil))
        XCTAssertEqual(first.terminalTTY, "/dev/ttys005")
    }

    // MARK: Hook version / reinstall — decision hook is now PreToolUse

    func testMergedHookCarriesCurrentVersionAndIsUpToDate() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        XCTAssertTrue(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }

    func testDecisionHookIsPreToolUseSynchronousWithTimeout() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        let hooks = merged["hooks"] as? [String: Any]
        let pre = hooks?["PreToolUse"] as? [[String: Any]]
        let inner = (pre?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(inner?["timeout"] as? Int, HookTimeouts.claudeHookTimeoutSeconds)
        XCTAssertNil(inner?["async"], "decision hook must be synchronous")
    }

    func testStaleV2InstallNeedsReinstall() {
        // A v2 install put the timeout on PermissionRequest, not PreToolUse.
        let staleV2: [String: Any] = ["hooks": ["PermissionRequest": [
            ["hooks": [["type": "command", "command": "\"/x/notchdeck-agent-hook\" --provider claude",
                        "timeout": HookTimeouts.claudeHookTimeoutSeconds, "notchdeckManaged": true,
                        "notchdeckHookVersion": 2]], "matcher": "*", "notchdeckManaged": true]]]]
        XCTAssertFalse(HookInstaller.configIsUpToDate(staleV2, provider: .claudeCode))
    }

    func testMergePreservesUserHooks() {
        let base: [String: Any] = ["hooks": ["PreToolUse": [
            ["hooks": [["type": "command", "command": "echo user"]], "matcher": "Bash"]]]]
        let merged = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        let pre = (merged["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        XCTAssertTrue(pre?.contains { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "echo user" } ?? false
        } ?? false, "user's own hook preserved")
        // Exactly one managed PreToolUse entry (no duplicates).
        XCTAssertEqual(pre?.filter { ($0["notchdeckManaged"] as? Bool) == true }.count, 1)
    }

    // MARK: Timeout hierarchy

    func testTimeoutHierarchy() {
        XCTAssertTrue(HookTimeouts.isValidHierarchy)
        XCTAssertLessThan(HookTimeouts.uiFallbackSeconds, HookTimeouts.helperHardDeadlineSeconds)
        XCTAssertLessThan(HookTimeouts.helperHardDeadlineSeconds,
                          TimeInterval(HookTimeouts.claudeHookTimeoutSeconds))
    }
}

import XCTest
@testable import NotchDeck

/// Approval delivery uses the provider PermissionRequest decision hook. Truthful
/// states: socket write / responseWritten is NOT provider acceptance.
final class AgentApprovalDeliveryTests: XCTestCase {

    /// A PermissionRequest event (the authoritative approval-creating channel).
    private func decisionEvent(requestID: String, toolUseID: String? = nil,
                               provider: TerminalAgentProvider = .claudeCode,
                               tty: String? = nil) -> TerminalAgentEvent {
        TerminalAgentEvent(type: .permissionRequested, provider: provider, sessionID: "s",
                           cwd: "/tmp", timestamp: 0, toolName: "Bash", tty: tty,
                           requestID: requestID, toolUseID: toolUseID ?? requestID)
    }

    // MARK: Exact provider response schema — PermissionRequest

    func testClaudeAllowSchemaIsPermissionRequest() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
    }

    func testClaudeDenySchemaIsPermissionRequest() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .deny, message: "Denied in NotchDeck"),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","interrupt":false,"message":"Denied in NotchDeck"},"hookEventName":"PermissionRequest"}}"#)
    }

    func testCodexAllowSchemaIsPermissionRequest() {
        XCTAssertEqual(PermissionResponse.json(provider: .codex, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
    }

    func testDecisionHookEventIsPermissionRequest() {
        XCTAssertEqual(PermissionResponse.decisionHookEvent, "PermissionRequest")
    }

    func testResponseUsesDecisionBehaviorShape() {
        let s = PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil)
        XCTAssertTrue(s.contains(#""decision":{"#))
        XCTAssertTrue(s.contains(#""behavior":"allow""#))
        XCTAssertFalse(s.contains("permissionDecision"))
    }

    func testStdoutLineSingleNewlineNoDiagnostics() {
        let line = PermissionResponse.stdoutLine(provider: .claudeCode, behavior: .allow, message: nil)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertFalse(line.lowercased().contains("provider="))
        XCTAssertFalse(line.lowercased().contains("socket"))
    }

    func testUnknownProviderDoesNotGuessASchema() {
        XCTAssertEqual(PermissionResponse.json(provider: .unknown, behavior: .deny, message: nil),
                       "")
    }

    // MARK: Approval creation / correlation / observer

    func testPermissionRequestCreatesApprovalWithCorrelationID() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: decisionEvent(requestID: "tuse_1"))
        XCTAssertEqual(s.approval?.requestID, "tuse_1")
        XCTAssertEqual(s.approval?.rawEventName, "PermissionRequest")
        XCTAssertEqual(s.approval?.state, .pending)
    }

    func testLegacyPreToolUseNeverCreatesApproval() {
        XCTAssertTrue(ApprovalClassifier.createsApproval(.permissionRequested))
        XCTAssertFalse(ApprovalClassifier.createsApproval(.toolPermissionRequested))
        let e = TerminalAgentEvent(type: .toolPermissionRequested, provider: .claudeCode,
                                   sessionID: "s", timestamp: 0, requestID: "r")
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e)
        XCTAssertNil(s.approval, "legacy PreToolUse must never create an approval")
    }

    func testToolStartedNeverCreatesApproval() {
        let e = TerminalAgentEvent(type: .toolStarted, provider: .claudeCode, sessionID: "s",
                                   timestamp: 0, toolName: "Bash")
        XCTAssertNil(TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e).approval)
    }

    func testDuplicatePermissionRequestDoesNotDuplicateApproval() {
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
        XCTAssertEqual(s.latestSummary, "Sent to Claude Code")
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
        XCTAssertEqual(done.latestSummary, "Claude Code continued")
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

    // MARK: Hook version / reinstall — decision hook is PermissionRequest

    func testMergedHookCarriesCurrentVersionAndIsUpToDate() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        XCTAssertTrue(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }

    func testDecisionHookIsPermissionRequestSynchronousWithTimeout() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        let hooks = merged["hooks"] as? [String: Any]
        let requests = hooks?["PermissionRequest"] as? [[String: Any]]
        let inner = (requests?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(inner?["timeout"] as? Int, HookTimeouts.claudeHookTimeoutSeconds)
        XCTAssertNil(inner?["async"], "decision hook must be synchronous")
    }

    func testStaleV2InstallNeedsReinstall() {
        // A v2 install has the obsolete response schema/version marker.
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
        let requests = (merged["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        // Exactly one managed PermissionRequest entry (no duplicates).
        XCTAssertEqual(requests?.filter { ($0["notchdeckManaged"] as? Bool) == true }.count, 1)
    }

    // MARK: Timeout hierarchy

    func testTimeoutHierarchy() {
        XCTAssertTrue(HookTimeouts.isValidHierarchy)
        XCTAssertLessThan(HookTimeouts.uiFallbackSeconds, HookTimeouts.helperHardDeadlineSeconds)
        XCTAssertLessThan(HookTimeouts.helperHardDeadlineSeconds,
                          TimeInterval(HookTimeouts.claudeHookTimeoutSeconds))
    }
}

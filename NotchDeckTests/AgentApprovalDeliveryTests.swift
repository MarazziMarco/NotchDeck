import XCTest
@testable import NotchDeck

/// Approval delivery: exact provider response schema, correlation, delivering →
/// delivered gating, fallback, and hook-version reinstall.
final class AgentApprovalDeliveryTests: XCTestCase {

    private func permEvent(requestID: String, provider: TerminalAgentProvider = .claudeCode,
                           tty: String? = nil) -> TerminalAgentEvent {
        TerminalAgentEvent(type: .permissionRequested, provider: provider, sessionID: "s",
                           cwd: "/tmp", timestamp: 0, tty: tty, requestID: requestID)
    }

    // MARK: Exact provider response schema (tests 4, 8–13)

    func testClaudeAllowSchema() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow"}}"#)
    }

    func testClaudeDenySchema() {
        XCTAssertEqual(PermissionResponse.json(provider: .claudeCode, behavior: .deny, message: "Denied in NotchDeck"),
            #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"deny","permissionDecisionReason":"Denied in NotchDeck"}}"#)
    }

    func testCodexAllowSchema() {
        XCTAssertEqual(PermissionResponse.json(provider: .codex, behavior: .allow, message: nil),
            #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow"}}"#)
    }

    func testCodexDenySchema() {
        let s = PermissionResponse.json(provider: .codex, behavior: .deny, message: nil)
        XCTAssertTrue(s.contains(#""permissionDecision":"deny""#))
        XCTAssertTrue(s.contains(#""hookEventName":"PermissionRequest""#))
    }

    func testResponseIsNotTheOldPreToolUseBehaviorShape() {
        let s = PermissionResponse.json(provider: .claudeCode, behavior: .allow, message: nil)
        XCTAssertFalse(s.contains(#""decision":{"#), "must not use the decision:{behavior} shape")
        XCTAssertFalse(s.contains("behavior"))
    }

    func testStdoutLineHasSingleTrailingNewlineAndNoDiagnostics() {
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

    // MARK: Correlation + approval creation (tests 1–3, 20)

    func testOnlyPermissionRequestCreatesApproval() {
        let tool = TerminalAgentEvent(type: .toolStarted, provider: .claudeCode, sessionID: "s",
                                      timestamp: 0, toolName: "Bash")
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: tool)
        XCTAssertNil(s.approval, "PreToolUse never creates an approval")
    }

    func testPermissionRequestCarriesCorrelationID() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(requestID: "req-42"))
        XCTAssertEqual(s.approval?.requestID, "req-42")
        XCTAssertEqual(s.pendingApprovalRequestID, "req-42")
        XCTAssertEqual(s.approval?.state, .pending)
    }

    func testDuplicatePermissionRequestDoesNotReplaceLiveApproval() {
        let id = UUID()
        let first = TerminalAgentBridge.reduce(existing: nil, id: id, event: permEvent(requestID: "r1"))
        let again = TerminalAgentBridge.reduce(existing: first, id: id, event: permEvent(requestID: "r1"))
        XCTAssertEqual(again.approval?.requestID, "r1")
        XCTAssertEqual(again.approval?.state, .pending, "idempotent — no second approval")
    }

    // MARK: Delivering → delivered gating (tests 6, 7, 14)

    func testDeliveryAckAppliesApprovedOnlyAfterAck() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(requestID: "r"))
        // User decided allow → delivering. No success yet.
        s.approval?.state = .sending
        s.approval?.decidedAllow = true
        XCTAssertNotEqual(s.latestSummary, "Approved")
        XCTAssertEqual(s.status, .waitingForApproval)
        // Helper acknowledged real delivery.
        TerminalAgentBridge.applyDeliveryAck(&s)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(s.latestSummary, "Approved")
        XCTAssertNil(s.approval, "approval dismissed after delivery")
    }

    func testDeliveryAckDenyInterrupts() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(requestID: "r"))
        s.approval?.state = .sending
        s.approval?.decidedAllow = false
        TerminalAgentBridge.applyDeliveryAck(&s)
        XCTAssertEqual(s.status, .interrupted)
        XCTAssertEqual(s.latestSummary, "Denied")
    }

    func testLateAckIsNoOp() {
        var s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(requestID: "r"))
        s.approval = nil                     // already dismissed / fell back
        s.latestSummary = "was-terminal"
        TerminalAgentBridge.applyDeliveryAck(&s)
        XCTAssertEqual(s.latestSummary, "was-terminal", "no stale mutation without a live approval")
    }

    // MARK: TTY capture/preserve (tests 11, 36)

    func testTTYCanonicalisedOnStore() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: permEvent(requestID: "r", tty: "ttys003"))
        XCTAssertEqual(s.terminalTTY, "/dev/ttys003")
    }

    func testStoredTTYNotOverwrittenByNil() {
        var first = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                               event: permEvent(requestID: "r", tty: "/dev/ttys005"))
        first = TerminalAgentBridge.reduce(existing: first, id: first.id,
                                           event: TerminalAgentEvent(type: .toolStarted, provider: .claudeCode,
                                                                     sessionID: "s", timestamp: 1, tty: nil))
        XCTAssertEqual(first.terminalTTY, "/dev/ttys005", "a later TTY-less event preserves the stored TTY")
    }

    // MARK: Hook version / reinstall (test 10, req 10)

    func testMergedHookCarriesCurrentVersionAndIsUpToDate() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        XCTAssertTrue(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }

    func testStaleInstallWithoutVersionNeedsReinstall() {
        let stale: [String: Any] = ["hooks": ["PermissionRequest": [
            ["hooks": [["type": "command", "command": "\"/x/notchdeck-agent-hook\" --provider claude",
                        "timeout": HookTimeouts.claudeHookTimeoutSeconds]], "matcher": "*"]]]]
        XCTAssertFalse(HookInstaller.configIsUpToDate(stale, provider: .claudeCode))
    }

    func testMergePreservesUserHooks() {
        let base: [String: Any] = ["hooks": ["PreToolUse": [
            ["hooks": [["type": "command", "command": "echo user"]], "matcher": "Bash"]]]]
        let merged = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/x/notchdeck-agent-hook")
        let hooks = merged["hooks"] as? [String: Any]
        let pre = hooks?["PreToolUse"] as? [[String: Any]]
        XCTAssertTrue(pre?.contains { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "echo user" } ?? false
        } ?? false, "user's own hook preserved")
    }

    // MARK: Timeout hierarchy (req 5)

    func testTimeoutHierarchy() {
        XCTAssertTrue(HookTimeouts.isValidHierarchy)
        XCTAssertLessThan(HookTimeouts.uiFallbackSeconds, HookTimeouts.helperHardDeadlineSeconds)
        XCTAssertLessThan(HookTimeouts.helperHardDeadlineSeconds,
                          TimeInterval(HookTimeouts.claudeHookTimeoutSeconds))
    }
}

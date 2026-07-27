import XCTest
@testable import NotchDeck

/// Truthful helper-termination semantics: a self-emitted "output closed" hint is
/// NOT proof of process termination; actual termination is the bridge-observed
/// socket EOF. These states are kept distinct.
final class AgentHelperLifecycleTruthTests: XCTestCase {

    private func answeredSession(state: PendingApproval.ResponseState,
                                 allow: Bool = true) -> AgentSession {
        var s = AgentSession(provider: .claudeCode, title: "t", projectPath: "/p",
                             status: .waitingForApproval, isManaged: false)
        s.isBridgeConnected = true
        var ap = PendingApproval(provider: .claudeCode, sessionID: "S", requestID: "TX1",
                                 toolUseID: "tu1", turnID: nil, rawEventName: "PermissionRequest",
                                 toolName: "Bash", summary: "run", receivedAt: Date(),
                                 expiresAt: Date().addingTimeInterval(120), state: state,
                                 handlingMode: .notchWithTerminalFallback, fallbackDeadline: nil,
                                 nativePromptExpected: true)
        ap.decidedAllow = allow
        s.approval = ap
        s.pendingApprovalRequestID = "TX1"
        return s
    }

    // Distinct states exist and are distinct.
    func testDistinctLifecycleStates() {
        let distinct: Set<PendingApproval.ResponseState> =
            [.sent, .providerOutputClosed, .helperTerminated, .delivered]
        XCTAssertEqual(distinct.count, 4)
    }

    // Self-emitted "output closed" → .providerOutputClosed, NOT termination.
    func testProviderOutputClosedIsNotTermination() {
        var s = answeredSession(state: .sent)
        TerminalAgentBridge.applyProviderOutputClosed(&s, requestID: "TX1")
        XCTAssertEqual(s.approval?.state, .providerOutputClosed)
        XCTAssertNotEqual(s.approval?.state, .helperTerminated, "self-report is not real termination")
    }

    // Socket EOF after an answered decision → real termination (.helperTerminated),
    // NOT a native fallback.
    func testEOFAfterAnswerMarksHelperTerminatedNotFallback() {
        for state in [PendingApproval.ResponseState.sent, .providerOutputClosed] {
            var s = answeredSession(state: state)
            TerminalAgentBridge.applyHelperTermination(&s, requestID: "TX1")
            XCTAssertEqual(s.approval?.state, .helperTerminated, "answered → clean termination")
            XCTAssertFalse(s.requiresAttention)
        }
    }

    // Socket EOF while still unanswered → the helper died without our decision →
    // release to native flow (.fellBack), never auto-approve.
    func testEOFWhileUnansweredFallsBackToTerminal() {
        for state in [PendingApproval.ResponseState.pending, .sending] {
            var s = answeredSession(state: state)
            TerminalAgentBridge.applyHelperTermination(&s, requestID: "TX1")
            XCTAssertEqual(s.approval?.state, .fellBack, "released to native flow")
            // Never a false success: not marked delivered/approved.
            XCTAssertNotEqual(s.approval?.state, .delivered)
            XCTAssertFalse(s.latestSummary?.contains("Approved") ?? false)
        }
    }

    // responseWritten still means only "Sent", never a false success.
    func testResponseWrittenIsSentNotApproved() {
        var s = answeredSession(state: .sending)
        TerminalAgentBridge.applyResponseWritten(&s, requestID: "TX1")
        XCTAssertEqual(s.approval?.state, .sent)
        XCTAssertTrue(s.latestSummary?.contains("Sent") ?? false)
        XCTAssertFalse(s.latestSummary?.contains("Approved") ?? true)
    }

    // "Continued" (.delivered) only on matching provider progression.
    func testDeliveredOnlyOnMatchingProgression() {
        let sent = answeredSession(state: .sent)
        // Non-matching tool-use id → no progression.
        let noMatch = TerminalAgentBridge.reduce(existing: sent, id: sent.id,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .claudeCode, sessionID: "S",
                                      timestamp: 1, toolUseID: "OTHER"))
        XCTAssertNotEqual(noMatch.approval?.state, .delivered)
        // Matching tool-use id → delivered / continued.
        let match = TerminalAgentBridge.reduce(existing: sent, id: sent.id,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .claudeCode, sessionID: "S",
                                      timestamp: 1, toolUseID: "tu1"))
        XCTAssertTrue(match.latestSummary?.contains("continued") ?? false)
    }

    // Legacy `.helperExited` still decodes (older persisted sessions).
    func testLegacyHelperExitedDecodes() throws {
        let json = "\"helperExited\"".data(using: .utf8)!
        let state = try JSONDecoder().decode(PendingApproval.ResponseState.self, from: json)
        XCTAssertEqual(state, .helperExited)
    }
}

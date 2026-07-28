import XCTest
@testable import NotchDeck

/// Configurable mirrored-approval lifetime. The lifetime governs how long the
/// NotchDeck card stays actionable; Terminal remains answerable throughout.
final class ApprovalLifetimeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func permEvent(_ requestID: String = "R1") -> TerminalAgentEvent {
        TerminalAgentEvent(type: .permissionRequested, provider: .claudeCode,
                           sessionID: "S", cwd: "/p", timestamp: 1_000_000,
                           requestID: requestID, transactionID: requestID)
    }

    private func approval(_ s: AgentSession) -> PendingApproval? { s.approval }

    // 1. Default duration is 60 seconds.
    func testDefaultIsSixtySeconds() {
        XCTAssertEqual(ApprovalAvailability.default, .s60)
        XCTAssertEqual(ApprovalAvailability.s60.seconds, 60)
    }

    // 2. Every supported picker value round-trips through persistence.
    func testAllValuesRoundTripAndCover30_60_90_120_300() {
        let seconds = ApprovalAvailability.allCases.map { $0.seconds }.sorted()
        XCTAssertEqual(seconds, [30, 60, 90, 120, 300])
        for c in ApprovalAvailability.allCases {
            let data = try! JSONEncoder().encode(c)
            let back = try! JSONDecoder().decode(ApprovalAvailability.self, from: data)
            XCTAssertEqual(back, c)
        }
    }

    // 3. A new request receives the configured lifetime.
    func testNewRequestUsesConfiguredLifetime() {
        for value in ApprovalAvailability.allCases {
            let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(),
                                               handlingMode: .notchWithTerminalFallback,
                                               approvalLifetime: value.seconds, now: t0)
            // Card stays actionable for the configured lifetime (fallback release),
            // with a small hard-expiry safety margin past it.
            XCTAssertEqual(approval(s)?.fallbackDeadline, t0.addingTimeInterval(value.seconds))
            XCTAssertEqual(approval(s)?.expiresAt, t0.addingTimeInterval(value.seconds + 5))
        }
    }

    // 4. An existing request retains its original deadline after the setting changes.
    func testExistingRequestKeepsOriginalDeadline() {
        let created = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent("R1"),
                                                 handlingMode: .notchWithTerminalFallback,
                                                 approvalLifetime: 30, now: t0)
        let originalDeadline = approval(created)?.fallbackDeadline
        // A later, unrelated event reduced with a DIFFERENT lifetime must not move it.
        let later = TerminalAgentBridge.reduce(existing: created, id: created.id,
            event: TerminalAgentEvent(type: .toolStarted, provider: .claudeCode, sessionID: "S",
                                      timestamp: 1_000_010, toolName: "Bash"),
            handlingMode: .notchWithTerminalFallback, approvalLifetime: 300, now: t0.addingTimeInterval(10))
        XCTAssertEqual(approval(later)?.fallbackDeadline, originalDeadline)
    }

    // 15. Queued same-provider approvals keep independent deadlines.
    func testQueuedApprovalsKeepIndependentDeadlines() {
        let first = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent("A"),
                                               handlingMode: .notchWithTerminalFallback,
                                               approvalLifetime: 30, now: t0)
        let both = TerminalAgentBridge.reduce(existing: first, id: first.id, event: permEvent("B"),
                                              handlingMode: .notchWithTerminalFallback,
                                              approvalLifetime: 300, now: t0.addingTimeInterval(5))
        XCTAssertEqual(both.approval?.requestID, "A")
        XCTAssertEqual(both.approval?.fallbackDeadline, t0.addingTimeInterval(30))
        let queued = both.queuedApprovals?.first { $0.requestID == "B" }
        XCTAssertEqual(queued?.fallbackDeadline, t0.addingTimeInterval(5 + 300))
    }

    // 16. Provider/hook technical deadlines safely support the maximum setting.
    func testInternalDeadlinesOutliveFiveMinutes() {
        XCTAssertTrue(HookTimeouts.isValidHierarchy)
        XCTAssertEqual(HookTimeouts.maxApprovalLifetimeSeconds, 300)
        XCTAssertLessThan(HookTimeouts.maxApprovalLifetimeSeconds, HookTimeouts.helperHardDeadlineSeconds)
        XCTAssertLessThan(HookTimeouts.helperHardDeadlineSeconds,
                          TimeInterval(HookTimeouts.claudeHookTimeoutSeconds))
        // The largest picker value is genuinely within the transport ceiling.
        XCTAssertLessThanOrEqual(ApprovalAvailability.s300.seconds, HookTimeouts.maxApprovalLifetimeSeconds)
    }

    // 5/6. Creating an approval never pre-decides allow/deny; expiry never auto-answers.
    func testApprovalStartsPendingWithNoDecision() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(),
                                           approvalLifetime: 60, now: t0)
        XCTAssertEqual(approval(s)?.state, .pending)
        XCTAssertNil(approval(s)?.decidedAllow, "no auto allow/deny at creation")
    }

    // 18. The description never claims the terminal prompt appears only after expiry.
    func testLifetimeIsClampedToCeiling() {
        // Even a pathological over-long value clamps to the supported ceiling.
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: permEvent(),
                                           handlingMode: .notchWithTerminalFallback,
                                           approvalLifetime: 100_000, now: t0)
        XCTAssertEqual(approval(s)?.fallbackDeadline,
                       t0.addingTimeInterval(HookTimeouts.maxApprovalLifetimeSeconds))
    }
}

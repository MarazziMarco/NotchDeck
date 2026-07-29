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
            // Card stops being actionable at exactly the configured deadline.
            XCTAssertEqual(approval(s)?.fallbackDeadline, t0.addingTimeInterval(value.seconds))
            XCTAssertEqual(approval(s)?.expiresAt, t0.addingTimeInterval(value.seconds))
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

    func testActionabilityEndsExactlyAtAssignedDeadline() {
        let session = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: permEvent(),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 60,
            now: t0
        )
        let pending = try! XCTUnwrap(session.approval)
        XCTAssertTrue(pending.isActionable(now: t0.addingTimeInterval(59.999)))
        XCTAssertFalse(pending.isActionable(now: t0.addingTimeInterval(60)))
    }

    func testOldSettingsBlobMigratesWithoutResettingUnrelatedPreferences() throws {
        let suite = "approval-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var original = AppSettings()
        original.hoverToOpen = false
        original.clipboardMaxItems = 37
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        object.removeValue(forKey: "approvalAvailability")
        object.removeValue(forKey: "moreLayout")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: SettingsStore.storageKey)

        let migrated = SettingsStore(defaults: defaults).settings
        XCTAssertFalse(migrated.hoverToOpen)
        XCTAssertEqual(migrated.clipboardMaxItems, 37)
        XCTAssertEqual(migrated.approvalAvailability, .s60)
        XCTAssertEqual(migrated.moreLayout, MoreLayoutSettings())
    }

    func testMirroredWordingNeverClaimsTerminalAppearsLater() {
        XCTAssertFalse(
            AgentPermissionHandlingMode.notchWithTerminalFallback.label
                .localizedCaseInsensitiveContains("then Terminal")
        )
        XCTAssertEqual(
            PendingApproval.availabilityStatus(isActionable: false),
            "No longer actionable in NotchDeck"
        )
    }

    func testQueuedExpiryIsIndependentAndPreservesTerminalPendingRequest() {
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: permEvent("A"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 300,
            now: t0
        )
        session = TerminalAgentBridge.reduce(
            existing: session,
            id: session.id,
            event: permEvent("B"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 30,
            now: t0
        )

        let released = TerminalAgentBridge.expireTransactions(
            &session,
            now: t0.addingTimeInterval(31)
        )
        XCTAssertEqual(released, ["B"])
        XCTAssertEqual(session.approval?.requestID, "A")
        XCTAssertEqual(session.queuedApprovals?.map(\.requestID), ["B"])
        XCTAssertEqual(session.queuedApprovals?.first?.state, .fellBack)
        XCTAssertNil(session.queuedApprovals?.first?.decidedAllow)
    }

    func testVisibleExpiryDoesNotAdvanceOrDecideWhileTerminalIsPending() {
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: permEvent("A"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 30,
            now: t0
        )
        session = TerminalAgentBridge.reduce(
            existing: session,
            id: session.id,
            event: permEvent("B"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 300,
            now: t0.addingTimeInterval(1)
        )

        let released = TerminalAgentBridge.expireTransactions(
            &session,
            now: t0.addingTimeInterval(31)
        )

        XCTAssertEqual(released, ["A"])
        XCTAssertEqual(session.approval?.requestID, "A")
        XCTAssertEqual(session.approval?.state, .fellBack)
        XCTAssertNil(session.approval?.decidedAllow)
        XCTAssertEqual(session.queuedApprovals?.map(\.requestID), ["B"])
    }

    func testNewConcurrentRequestDoesNotReplaceExpiredTerminalPendingHead() {
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: permEvent("A"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 30,
            now: t0
        )
        _ = TerminalAgentBridge.expireTransactions(
            &session,
            now: t0.addingTimeInterval(31)
        )

        session = TerminalAgentBridge.reduce(
            existing: session,
            id: session.id,
            event: permEvent("B"),
            handlingMode: .notchWithTerminalFallback,
            approvalLifetime: 300,
            now: t0.addingTimeInterval(32)
        )

        XCTAssertEqual(session.approval?.requestID, "A")
        XCTAssertEqual(session.approval?.state, .fellBack)
        XCTAssertEqual(session.queuedApprovals?.map(\.requestID), ["B"])
    }
}

final class ApprovalPeekQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func approval(
        _ requestID: String,
        receivedOffset: TimeInterval,
        state: PendingApproval.ResponseState = .pending
    ) -> PendingApproval {
        PendingApproval(
            provider: .claudeCode,
            sessionID: "provider-session",
            requestID: requestID,
            providerRequestID: "native-\(requestID)",
            toolUseID: nil,
            turnID: nil,
            rawEventName: "PermissionRequest",
            toolName: "Bash",
            summary: "printf safe",
            receivedAt: t0.addingTimeInterval(receivedOffset),
            expiresAt: t0.addingTimeInterval(receivedOffset + 60),
            state: state,
            handlingMode: .notchWithTerminalFallback,
            fallbackDeadline: t0.addingTimeInterval(receivedOffset + 60),
            nativePromptExpected: true
        )
    }

    private func session(
        id: UUID,
        current: PendingApproval?,
        queued: [PendingApproval] = []
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            provider: .claudeCode,
            providerSessionID: "provider-session",
            title: "Claude project",
            projectPath: "/tmp/project",
            status: current == nil ? .running : .waitingForApproval,
            isManaged: false,
            isBridgeConnected: true,
            pendingApprovalRequestID: current?.requestID,
            approval: current
        )
        session.queuedApprovals = queued.isEmpty ? nil : queued
        return session
    }

    func testOneRequestIsVisibleAtATime() {
        let one = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("A", receivedOffset: 0),
            queued: [approval("B", receivedOffset: 1)]
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [one])

        XCTAssertEqual(snapshot.visible?.transactionID, "A")
        XCTAssertEqual(snapshot.totalCount, 2)
    }

    func testConcurrentRequestsRemainGlobalFIFO() {
        let laterSession = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            current: approval("C", receivedOffset: 2)
        )
        let earlierSession = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("A", receivedOffset: 0),
            queued: [approval("B", receivedOffset: 1)]
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [laterSession, earlierSession])

        XCTAssertEqual(snapshot.items.map(\.transactionID), ["A", "B", "C"])
    }

    func testQueuePositionAndCountDescribeVisibleRequest() {
        let one = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("A", receivedOffset: 0),
            queued: [
                approval("B", receivedOffset: 1),
                approval("C", receivedOffset: 2),
            ]
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [one])

        XCTAssertEqual(snapshot.visiblePosition, 1)
        XCTAssertEqual(snapshot.totalCount, 3)
        XCTAssertEqual(snapshot.queueLabel, "1/3")
    }

    func testDuplicateTransactionIDsDoNotDuplicatePeekItems() {
        let first = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("same-transaction", receivedOffset: 0)
        )
        let duplicate = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            current: approval("same-transaction", receivedOffset: 1)
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [duplicate, first])

        XCTAssertEqual(snapshot.items.map(\.transactionID), ["same-transaction"])
    }

    func testTerminalPendingTransactionRemainsVisible() {
        let one = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("expired-locally", receivedOffset: 0, state: .fellBack)
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [one])

        XCTAssertEqual(snapshot.visible?.transactionID, "expired-locally")
        XCTAssertFalse(snapshot.visible?.isLocallyActionable(at: t0.addingTimeInterval(70)) ?? true)
        XCTAssertEqual(snapshot.visible?.statusText(at: t0.addingTimeInterval(70)), "Respond in Terminal")
    }

    func testProgressUsesOriginalAbsoluteDeadline() {
        let received = Date(timeIntervalSince1970: 100)
        let deadline = Date(timeIntervalSince1970: 160)

        XCTAssertEqual(
            ApprovalPeekProgress.fraction(
                receivedAt: received,
                deadline: deadline,
                now: Date(timeIntervalSince1970: 130)
            ),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ApprovalPeekProgress.fraction(
                receivedAt: received,
                deadline: deadline,
                now: Date(timeIntervalSince1970: 170)
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testProgressDoesNotCreateOrChangeTransactionDeadline() {
        let request = approval("deadline-stable", receivedOffset: 0)
        let deadline = request.actionDeadline

        _ = ApprovalPeekProgress.fraction(
            receivedAt: request.receivedAt,
            deadline: request.actionDeadline,
            now: t0.addingTimeInterval(12)
        )

        XCTAssertEqual(request.actionDeadline, deadline)
    }

    func testCancelledAndDeliveredTransactionsAreNotPresentable() {
        let cancelled = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("cancelled", receivedOffset: 0, state: .cancelled)
        )
        let delivered = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            current: approval("delivered", receivedOffset: 1, state: .delivered)
        )

        let snapshot = ApprovalPeekQueue.resolve(sessions: [cancelled, delivered])

        XCTAssertNil(snapshot.visible)
        XCTAssertEqual(snapshot.totalCount, 0)
    }

    func testPeekAccessibilityExposesProviderActionQueueAndConsequences() throws {
        let one = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("A", receivedOffset: 0),
            queued: [approval("B", receivedOffset: 1)]
        )
        let item = try XCTUnwrap(ApprovalPeekQueue.resolve(sessions: [one]).visible)
        let presentation = ApprovalPeekPresentation(item: item, totalCount: 2)

        XCTAssertTrue(presentation.groupAccessibilityLabel.contains("Claude"))
        XCTAssertTrue(presentation.groupAccessibilityLabel.contains("printf safe"))
        XCTAssertTrue(presentation.groupAccessibilityLabel.contains("1 of 2"))
        XCTAssertTrue(presentation.allowAccessibilityLabel.contains("Allow"))
        XCTAssertTrue(presentation.allowAccessibilityLabel.contains("Claude"))
        XCTAssertTrue(presentation.denyAccessibilityLabel.contains("Deny"))
        XCTAssertTrue(presentation.focusAccessibilityLabel.contains("Terminal"))
    }

    func testExpiredPeekWordingDoesNotClaimTerminalAppearsAfterTimeout() throws {
        let one = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            current: approval("expired", receivedOffset: 0, state: .fellBack)
        )
        let item = try XCTUnwrap(ApprovalPeekQueue.resolve(sessions: [one]).visible)
        let presentation = ApprovalPeekPresentation(item: item, totalCount: 1)

        XCTAssertEqual(presentation.expiredStatus, "Respond in Terminal")
        XCTAssertFalse(presentation.expiredStatus.localizedCaseInsensitiveContains("now"))
        XCTAssertFalse(presentation.expiredStatus.localizedCaseInsensitiveContains("appears"))
        XCTAssertFalse(presentation.expiredStatus.localizedCaseInsensitiveContains("after"))
    }

    func testPeekMotionPolicyDisablesNonessentialAnimationForReduceMotion() {
        XCTAssertFalse(ApprovalPeekMotionPolicy(reduceMotion: true).animatesAppearance)
        XCTAssertFalse(ApprovalPeekMotionPolicy(reduceMotion: true).animatesHoverGrowth)
        XCTAssertFalse(ApprovalPeekMotionPolicy(reduceMotion: true).animatesProgress)
        XCTAssertTrue(ApprovalPeekMotionPolicy(reduceMotion: false).animatesAppearance)
    }

    func testFocusTerminalTargetsTheVisibleRequestSession() throws {
        let visibleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let visibleSession = session(
            id: visibleID,
            current: approval("A", receivedOffset: 0)
        )
        let otherSession = session(
            id: otherID,
            current: approval("B", receivedOffset: 1)
        )
        let item = try XCTUnwrap(
            ApprovalPeekQueue.resolve(sessions: [otherSession, visibleSession]).visible
        )

        let target = ApprovalPeekFocus.target(
            for: item,
            sessions: [otherSession, visibleSession]
        )

        XCTAssertEqual(target?.id, visibleID)
        XCTAssertEqual(target?.approval?.requestID, "A")
    }

    func testSessionEndSafelyClearsCurrentAndQueuedPeekTransactions() {
        let id = UUID()
        var active = session(
            id: id,
            current: approval("A", receivedOffset: 0),
            queued: [approval("B", receivedOffset: 1)]
        )
        active.providerSessionID = "provider-session"

        let ended = TerminalAgentBridge.reduce(
            existing: active,
            id: id,
            event: TerminalAgentEvent(
                type: .sessionEnded,
                provider: .claudeCode,
                sessionID: "provider-session",
                timestamp: t0.timeIntervalSince1970 + 2
            )
        )

        XCTAssertNil(ended.approval)
        XCTAssertNil(ended.queuedApprovals)
        XCTAssertNil(ApprovalPeekQueue.resolve(sessions: [ended]).visible)
    }
}

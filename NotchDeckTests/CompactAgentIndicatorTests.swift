import XCTest
@testable import NotchDeck

final class CompactAgentIndicatorModelTests: XCTestCase {
    private func resolve(
        active: Int = 0,
        approvals: Int = 0,
        inputs: Int = 0,
        transactions: [PendingApproval.ResponseState] = [],
        display: CompactAgentsDisplay = .activeCount
    ) -> CompactAgentIndicatorModel {
        CompactAgentIndicatorModel.resolve(
            CompactAgentIndicatorInputs(
                activeSessionCount: active,
                pendingApprovalCount: approvals,
                inputRequiredCount: inputs,
                transactionStates: transactions,
                displayPreference: display
            )
        )
    }

    func testNoSessionsProducesHiddenState() {
        XCTAssertEqual(resolve(), .hidden)
        XCTAssertFalse(resolve().isVisible)
    }

    func testOneActiveSessionProducesOneAggregateCount() {
        XCTAssertEqual(resolve(active: 1), .activeSessions(count: 1))
        XCTAssertEqual(resolve(active: 1).compactCountText, "1")
    }

    func testMultipleActiveSessionsProduceOneAggregateCount() {
        XCTAssertEqual(resolve(active: 3), .activeSessions(count: 3))
        XCTAssertEqual(resolve(active: 3).compactCountText, "3")
    }

    func testApprovalOverridesOrdinaryActiveState() {
        XCTAssertEqual(
            resolve(active: 3, approvals: 1),
            .approvalRequired(count: 1)
        )
    }

    func testInputRequestOverridesOrdinaryActiveState() {
        XCTAssertEqual(
            resolve(active: 3, inputs: 2),
            .inputRequired(count: 2)
        )
    }

    func testDeliveryFailureHasHighestPriority() {
        XCTAssertEqual(
            resolve(
                active: 4,
                approvals: 3,
                inputs: 2,
                transactions: [.sending, .fellBack, .deliveryFailed]
            ),
            .deliveryFailed
        )
    }

    func testTerminalFallbackOverridesPendingApproval() {
        XCTAssertEqual(
            resolve(active: 2, approvals: 1, transactions: [.fellBack]),
            .terminalFallback
        )
    }

    func testMultipleApprovalsProduceOneApprovalCount() {
        let model = resolve(active: 4, approvals: 3)
        XCTAssertEqual(model, .approvalRequired(count: 3))
        XCTAssertEqual(model.compactCountText, "3")
    }

    func testDeliveryInProgressOverridesActiveState() {
        for state in [
            PendingApproval.ResponseState.sending,
            .sent,
            .helperExited
        ] {
            XCTAssertEqual(
                resolve(active: 2, transactions: [state]),
                .deliveryInProgress
            )
        }
    }

    func testApprovalAndInputOverrideDeliveryInProgress() {
        XCTAssertEqual(
            resolve(
                active: 2,
                approvals: 1,
                inputs: 1,
                transactions: [.sending]
            ),
            .approvalRequired(count: 1)
        )
        XCTAssertEqual(
            resolve(active: 2, inputs: 1, transactions: [.sending]),
            .inputRequired(count: 1)
        )
    }

    func testCountsOverNineUseDeliberateCompactRepresentation() {
        XCTAssertEqual(resolve(active: 9).compactCountText, "9")
        XCTAssertEqual(resolve(active: 10).compactCountText, "9+")
        XCTAssertEqual(resolve(approvals: 42).compactCountText, "9+")
    }

    func testHiddenPreferenceSuppressesOnlyOrdinaryActiveState() {
        XCTAssertEqual(resolve(active: 2, display: .hidden), .hidden)
        XCTAssertEqual(
            resolve(active: 2, approvals: 1, display: .hidden),
            .approvalRequired(count: 1)
        )
    }

    func testCompactLabelsNeverContainEllipsisOrPrivateNames() {
        let forbidden = ["...", "…", "Claude", "Codex", "project-secret", "session-secret"]
        let models: [CompactAgentIndicatorModel] = [
            .activeSessions(count: 3),
            .approvalRequired(count: 2),
            .inputRequired(count: 1),
            .deliveryInProgress,
            .deliveryFailed,
            .terminalFallback
        ]

        for model in models {
            let strings = [model.conciseLabel, model.compactCountText, model.accessibilityLabel]
                .compactMap { $0 }
            for value in strings {
                for fragment in forbidden {
                    XCTAssertFalse(value.localizedCaseInsensitiveContains(fragment))
                }
            }
        }
    }

    func testAccessibilityLabelsAreSingleMeaningfulPhrases() {
        XCTAssertEqual(
            CompactAgentIndicatorModel.activeSessions(count: 3).accessibilityLabel,
            "3 active agent sessions"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.approvalRequired(count: 1).accessibilityLabel,
            "1 agent approval required"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.approvalRequired(count: 2).accessibilityLabel,
            "2 agent approvals required"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.inputRequired(count: 1).accessibilityLabel,
            "1 agent input required"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.deliveryInProgress.accessibilityLabel,
            "Agent response delivery in progress"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.deliveryFailed.accessibilityLabel,
            "Agent approval delivery failed"
        )
        XCTAssertEqual(
            CompactAgentIndicatorModel.terminalFallback.accessibilityLabel,
            "Respond to agent in Terminal"
        )
    }
}

final class CompactAgentIndicatorInputDerivationTests: XCTestCase {
    private func approvalSession(
        requestID: String,
        state: PendingApproval.ResponseState = .pending
    ) -> AgentSession {
        let event = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .claudeCode,
            sessionID: "session-\(requestID)",
            cwd: "/tmp",
            timestamp: Date().timeIntervalSince1970,
            requestID: requestID
        )
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: event,
            now: Date()
        )
        session.approval?.state = state
        return session
    }

    func testSessionDerivationAggregatesCurrentAndQueuedApprovals() {
        var first = approvalSession(requestID: "one")
        let queued = approvalSession(requestID: "queued").approval
        first.queuedApprovals = [queued].compactMap { $0 }
        let second = approvalSession(requestID: "two")

        let inputs = CompactAgentIndicatorInputs.resolve(
            activeSessions: [first, second],
            displayPreference: .activeCount
        )

        XCTAssertEqual(inputs.activeSessionCount, 2)
        XCTAssertEqual(inputs.pendingApprovalCount, 3)
        XCTAssertEqual(
            CompactAgentIndicatorModel.resolve(inputs),
            .approvalRequired(count: 3)
        )
    }

    func testSessionDerivationAggregatesInputAndTransactionStates() {
        var input = AgentSession(
            provider: .codex,
            title: "private-session-name",
            projectPath: "/private/project",
            status: .waitingForInput
        )
        input.terminalPresence = .present
        let failed = approvalSession(requestID: "failed", state: .deliveryFailed)

        let inputs = CompactAgentIndicatorInputs.resolve(
            activeSessions: [input, failed],
            displayPreference: .activeCount
        )

        XCTAssertEqual(inputs.inputRequiredCount, 1)
        XCTAssertEqual(inputs.transactionStates, [.deliveryFailed])
        XCTAssertEqual(
            CompactAgentIndicatorModel.resolve(inputs),
            .deliveryFailed
        )
    }
}

final class CompactAgentActivityFactoryTests: XCTestCase {
    func testHiddenStateCreatesNoActivityOrInvisibleInteractionTarget() {
        XCTAssertNil(CompactAgentActivityFactory.make(for: .hidden))
    }

    func testActivityCarriesOneSemanticAgentModelOnly() throws {
        let activity = try XCTUnwrap(
            CompactAgentActivityFactory.make(for: .approvalRequired(count: 2))
        )
        XCTAssertEqual(activity.tapTarget, .face(.agents))
        XCTAssertEqual(activity.slot.compactAgentIndicator, .approvalRequired(count: 2))
        XCTAssertNil(activity.slot.symbol)
        XCTAssertNil(activity.slot.text)
        XCTAssertNil(activity.slot.badge)
        XCTAssertNil(activity.slot.providerVendor)
    }

    func testUrgentStatesAreExclusiveAndActiveStateIsNot() throws {
        let active = try XCTUnwrap(
            CompactAgentActivityFactory.make(for: .activeSessions(count: 2))
        )
        let approval = try XCTUnwrap(
            CompactAgentActivityFactory.make(for: .approvalRequired(count: 1))
        )
        XCTAssertFalse(active.exclusive)
        XCTAssertTrue(approval.exclusive)
    }
}

final class CompactAgentFocusCoexistenceTests: XCTestCase {
    private func focus(_ remaining: String = "12:00") -> ResolvedActivity {
        ResolvedActivity(
            id: "pomodoro",
            priority: .pomodoroRunning,
            slot: WingSlot(
                symbol: "timer",
                text: remaining,
                progress: 0.5,
                tint: .running,
                monospacedDigits: true,
                emphasize: true
            ),
            preferredWing: .leading,
            tapTarget: .module("pomodoro"),
            splitLeading: WingSlot(symbol: "timer", progress: 0.5, tint: .running),
            splitTrailing: WingSlot(
                text: remaining,
                tint: .running,
                monospacedDigits: true,
                emphasize: true
            )
        )
    }

    func testFocusSuppressesOnlyOrdinaryActiveAgentIndicator() throws {
        let agents = try XCTUnwrap(
            CompactAgentActivityFactory.make(for: .activeSessions(count: 3))
        )
        let layout = LiveActivityCoordinator.resolve([focus(), agents])

        XCTAssertEqual(layout.leading?.symbol, "timer")
        XCTAssertEqual(layout.trailing?.text, "12:00")
        XCTAssertNil(layout.compactAgentIndicator)
        XCTAssertEqual(layout.tapTarget, .module("pomodoro"))
    }

    func testUrgentApprovalRemainsVisibleDuringFocus() throws {
        let approval = try XCTUnwrap(
            CompactAgentActivityFactory.make(for: .approvalRequired(count: 1))
        )
        let layout = LiveActivityCoordinator.resolve([focus(), approval])

        XCTAssertEqual(layout.compactAgentIndicator, .approvalRequired(count: 1))
        XCTAssertEqual(layout.tapTarget, .face(.agents))
        XCTAssertFalse(layout.isFocusTimer)
    }
}

final class CompactAgentGeometryTests: XCTestCase {
    func testAgentContentRectStaysInsideRightWingSafeInsets() {
        let wing = CompactAgentIndicatorGeometry.rightWingRect
        let content = CompactAgentIndicatorGeometry.rightWingContentRect

        XCTAssertTrue(wing.contains(content))
        XCTAssertGreaterThanOrEqual(
            content.minX - wing.minX,
            CompactAgentIndicatorGeometry.notchSafeInset
        )
        XCTAssertGreaterThanOrEqual(
            wing.maxX - content.maxX,
            CompactAgentIndicatorGeometry.outerEdgeInset
        )
    }

    func testZeroOneManyPreserveStableGeometryAssumptions() {
        XCTAssertEqual(
            CompactAgentIndicatorGeometry.extraWidth(for: .hidden),
            0
        )

        let visible: [CompactAgentIndicatorModel] = [
            .activeSessions(count: 1),
            .activeSessions(count: 9),
            .activeSessions(count: 10),
            .approvalRequired(count: 1),
            .approvalRequired(count: 12),
            .deliveryFailed
        ]
        let widths = Set(visible.map(CompactAgentIndicatorGeometry.extraWidth(for:)))
        XCTAssertEqual(widths.count, 1)
        XCTAssertEqual(widths.first, CompactAgentIndicatorGeometry.totalExtraWidth)
    }

    func testFocusAndAgentProfilesRemainDistinctEvenWithSameSlotCount() {
        let focusLayout = LiveActivityLayout(
            leading: WingSlot(symbol: "timer", progress: 0.5),
            trailing: WingSlot(text: "12:00", monospacedDigits: true, emphasize: true)
        )
        let approvalLayout = LiveActivityLayout(
            trailing: WingSlot(compactAgentIndicator: .approvalRequired(count: 1))
        )

        XCTAssertEqual(CompactGeometrySignature.resolve(focusLayout), .focus)
        XCTAssertEqual(CompactGeometrySignature.resolve(approvalLayout), .agent)
        XCTAssertNotEqual(
            CompactGeometrySignature.resolve(focusLayout),
            CompactGeometrySignature.resolve(approvalLayout)
        )
    }
}

final class CompactNotchPresentationPolicyTests: XCTestCase {
    func testCompactAndExpandedContentAreMutuallyExclusive() {
        for state in [
            NotchPresentationState.compact,
            .peeking,
            .expanded
        ] {
            XCTAssertNotEqual(
                CompactNotchPresentationPolicy.showsCompact(in: state),
                CompactNotchPresentationPolicy.showsExpanded(in: state)
            )
        }
        XCTAssertTrue(CompactNotchPresentationPolicy.showsCompact(in: .compact))
        XCTAssertTrue(CompactNotchPresentationPolicy.showsCompact(in: .peeking))
        XCTAssertFalse(CompactNotchPresentationPolicy.showsCompact(in: .expanded))
    }

    func testTypedAgentIndicatorOwnsItsHitTarget() {
        let agentLayout = LiveActivityLayout(
            trailing: WingSlot(compactAgentIndicator: .activeSessions(count: 1)),
            tapTarget: .face(.agents)
        )
        let genericLayout = LiveActivityLayout(
            trailing: WingSlot(symbol: "music.note"),
            tapTarget: .module("now-playing")
        )

        XCTAssertFalse(
            CompactNotchInteractionPolicy.containerHandlesTap(for: agentLayout)
        )
        XCTAssertTrue(
            CompactNotchInteractionPolicy.containerHandlesTap(for: genericLayout)
        )
    }
}

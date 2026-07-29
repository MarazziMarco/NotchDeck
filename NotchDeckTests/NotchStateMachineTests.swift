import XCTest
@testable import NotchDeck

final class NotchStateMachineTests: XCTestCase {

    func testHoverCannotOpenAnEmptyPeek() {
        var m = NotchStateMachine()
        XCTAssertEqual(m.presentation, .compact)
        XCTAssertFalse(m.apply(.hoverBegan))
        XCTAssertEqual(m.presentation, .compact)
    }

    func testApprovalRequestTransitionsCompactToPeek() {
        var m = NotchStateMachine()

        XCTAssertTrue(m.apply(.approvalPeekAvailable(true)))

        XCTAssertEqual(m.presentation, .peeking)
    }

    func testClearingFinalApprovalReturnsPeekToCompact() {
        var m = NotchStateMachine()
        m.apply(.approvalPeekAvailable(true))

        XCTAssertTrue(m.apply(.approvalPeekAvailable(false)))

        XCTAssertEqual(m.presentation, .compact)
    }

    func testCompactRequestKeepsPeekWhileApprovalRemains() {
        var m = NotchStateMachine()
        m.apply(.approvalPeekAvailable(true))
        m.apply(.clicked)

        XCTAssertTrue(m.apply(.requestCompact))

        XCTAssertEqual(m.presentation, .peeking)
    }

    func testClickExpandsAndStaysOnHoverEnd() {
        var m = NotchStateMachine()
        m.apply(.clicked)
        XCTAssertEqual(m.presentation, .expanded)
        // Hover ending must NOT collapse a click-opened panel.
        XCTAssertFalse(m.apply(.hoverEnded))
        XCTAssertEqual(m.presentation, .expanded)
    }

    func testLockPreventsExpansion() {
        var m = NotchStateMachine()
        m.apply(.setLocked(true))
        XCTAssertFalse(m.apply(.clicked))
        XCTAssertEqual(m.presentation, .compact)
        m.apply(.setLocked(false))
        XCTAssertTrue(m.apply(.clicked))
        XCTAssertEqual(m.presentation, .expanded)
    }

    func testDragEntersExpandsToUtilities() {
        var m = NotchStateMachine()
        m.switchFace(to: .agents)
        m.apply(.dragEntered)
        XCTAssertEqual(m.presentation, .expanded)
        XCTAssertEqual(m.face, .utilities)
    }

    func testEscapeAndOutsideCollapse() {
        var m = NotchStateMachine()
        m.apply(.clicked)
        m.apply(.escapePressed)
        XCTAssertEqual(m.presentation, .compact)
        m.apply(.clicked)
        m.apply(.outsideClicked)
        XCTAssertEqual(m.presentation, .compact)
    }

    func testRedundantTransitionsAreNoOps() {
        var m = NotchStateMachine()
        XCTAssertTrue(m.apply(.requestCompact) == false) // already compact
        m.apply(.clicked)
        XCTAssertFalse(m.apply(.clicked))                // already expanded
    }

    func testLockBlocksRequestExpandButAllowsCompact() {
        var m = NotchStateMachine()
        m.apply(.requestExpand(.agents))
        XCTAssertEqual(m.presentation, .expanded)
        // Pinned open: a lock is set while expanded (the "pin" gesture).
        m.apply(.setLocked(true))
        XCTAssertEqual(m.presentation, .expanded)
        // A fresh expand request while locked is a no-op...
        XCTAssertFalse(m.apply(.requestExpand(.utilities)))
        // ...but an explicit compact (Escape / outside click) still collapses.
        XCTAssertTrue(m.apply(.requestCompact))
        XCTAssertEqual(m.presentation, .compact)
    }

    func testRequestExpandSetsFace() {
        var m = NotchStateMachine()
        m.apply(.requestExpand(.agents))
        XCTAssertEqual(m.face, .agents)
    }

    func testSwitchFaceToggles() {
        var m = NotchStateMachine()
        XCTAssertEqual(m.face, .utilities)
        XCTAssertTrue(m.switchFace())
        XCTAssertEqual(m.face, .agents)
        XCTAssertFalse(m.switchFace(to: .agents))        // no change
    }

    @MainActor
    func testApprovalStoreDrivesCompactToPeekWithoutOpeningAgents() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-presentation-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )

        store.upsert(Self.sessionWithApproval())

        XCTAssertEqual(coordinator.snapshot.totalCount, 1)
        XCTAssertEqual(appState.presentation, .peeking)
        XCTAssertEqual(appState.face, .utilities)
    }

    @MainActor
    func testAuthoritativeResolutionClearsPeekImmediately() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-resolution-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let session = Self.sessionWithApproval()
        store.upsert(session)

        store.update(id: session.id) {
            $0.approval = nil
            $0.requiresAttention = false
        }

        XCTAssertNil(coordinator.snapshot.visible)
        XCTAssertEqual(appState.presentation, .compact)
    }

    @MainActor
    func testApprovalProjectionDoesNotReplaceExpandedState() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-expanded-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        appState.expand(face: .utilities)

        store.upsert(Self.sessionWithApproval())

        XCTAssertEqual(coordinator.snapshot.totalCount, 1)
        XCTAssertEqual(appState.presentation, .expanded)
        XCTAssertEqual(appState.face, .utilities)
    }

    @MainActor
    func testDismissingPeekCompactsWithoutResolvingApproval() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-dismiss-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let session = Self.sessionWithApproval()
        let originalDeadline = session.approval?.actionDeadline
        store.upsert(session)

        coordinator.dismissCurrentPeek()

        XCTAssertTrue(coordinator.isSuppressed)
        XCTAssertEqual(appState.presentation, .compact)
        XCTAssertEqual(store.session(id: session.id)?.approval?.requestID, "transaction")
        XCTAssertEqual(store.session(id: session.id)?.approval?.actionDeadline, originalDeadline)
        XCTAssertNil(store.session(id: session.id)?.approval?.decidedAllow)
    }

    @MainActor
    func testDismissedPeekStaysCompactForUpdatesToSameTransactions() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-dismiss-update-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let session = Self.sessionWithApproval()
        store.upsert(session)
        coordinator.dismissCurrentPeek()

        store.update(id: session.id) {
            $0.latestSummary = "still pending"
        }

        XCTAssertTrue(coordinator.isSuppressed)
        XCTAssertEqual(appState.presentation, .compact)
        XCTAssertEqual(coordinator.snapshot.visible?.transactionID, "transaction")
    }

    @MainActor
    func testNewTransactionReopensDismissedPeek() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-dismiss-new-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let first = Self.sessionWithApproval()
        store.upsert(first)
        coordinator.dismissCurrentPeek()

        let template = Self.sessionWithApproval()
        var second = AgentSession(
            id: UUID(),
            provider: template.provider,
            title: template.title,
            projectPath: template.projectPath,
            status: template.status,
            requiresAttention: template.requiresAttention,
            isManaged: template.isManaged,
            isBridgeConnected: template.isBridgeConnected,
            pendingApprovalRequestID: "transaction-2",
            approval: template.approval
        )
        second.pendingApprovalRequestID = "transaction-2"
        second.approval?.requestID = "transaction-2"
        second.approval?.receivedAt = Date().addingTimeInterval(1)
        let secondDeadline = Date().addingTimeInterval(61)
        second.approval?.expiresAt = secondDeadline
        second.approval?.fallbackDeadline = secondDeadline
        store.upsert(second)

        XCTAssertFalse(coordinator.isSuppressed)
        XCTAssertEqual(appState.presentation, .peeking)
        XCTAssertEqual(coordinator.snapshot.totalCount, 2)
    }

    @MainActor
    func testExpandPeekOpensFullAgentsWithoutResolvingApproval() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-expand-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let session = Self.sessionWithApproval()
        store.upsert(session)

        coordinator.openExpanded()

        XCTAssertEqual(appState.presentation, .expanded)
        XCTAssertEqual(appState.face, .agents)
        XCTAssertEqual(store.session(id: session.id)?.approval?.requestID, "transaction")
        XCTAssertNil(store.session(id: session.id)?.approval?.decidedAllow)
    }

    private static func sessionWithApproval() -> AgentSession {
        let now = Date()
        return AgentSession(
            provider: .claudeCode,
            title: "Project",
            projectPath: "/tmp/project",
            status: .waitingForApproval,
            requiresAttention: true,
            isManaged: false,
            isBridgeConnected: true,
            pendingApprovalRequestID: "transaction",
            approval: PendingApproval(
                provider: .claudeCode,
                sessionID: "provider-session",
                requestID: "transaction",
                toolUseID: "tool-use",
                turnID: nil,
                rawEventName: "PermissionRequest",
                toolName: "Bash",
                summary: "make test",
                receivedAt: now,
                expiresAt: now.addingTimeInterval(60),
                state: .pending,
                handlingMode: .notchWithTerminalFallback,
                fallbackDeadline: now.addingTimeInterval(60),
                nativePromptExpected: true
            )
        )
    }
}

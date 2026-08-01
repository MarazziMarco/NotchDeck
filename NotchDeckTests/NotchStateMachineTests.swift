import XCTest
import Combine
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

    func testClickFromPeekOpensExpanded() {
        var m = NotchStateMachine()
        m.apply(.approvalPeekAvailable(true))

        XCTAssertTrue(m.apply(.clicked))
        XCTAssertEqual(m.presentation, .expanded)
    }

    func testExplicitUtilitiesExpandWorksFromPeek() {
        var m = NotchStateMachine()
        m.apply(.approvalPeekAvailable(true))

        XCTAssertTrue(m.apply(.requestExpand(.utilities)))
        XCTAssertEqual(m.presentation, .expanded)
        XCTAssertEqual(m.face, .utilities)
    }

    func testExplicitAgentsExpandWorksFromPeek() {
        var m = NotchStateMachine()
        m.apply(.approvalPeekAvailable(true))

        XCTAssertTrue(m.apply(.requestExpand(.agents)))
        XCTAssertEqual(m.presentation, .expanded)
        XCTAssertEqual(m.face, .agents)
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

    @MainActor
    func testExpandPeekOpensUtilitiesWithoutMutatingApproval() {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-utilities-\(UUID()).json")
        let coordinator = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let session = Self.sessionWithApproval()
        let deadline = session.approval?.actionDeadline
        store.upsert(session)

        coordinator.openExpanded(face: .utilities)

        XCTAssertEqual(appState.presentation, .expanded)
        XCTAssertEqual(appState.face, .utilities)
        XCTAssertEqual(store.session(id: session.id)?.approval?.actionDeadline, deadline)
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

@MainActor
final class PeekNavigationRegressionTests: XCTestCase {
    private var coordinators: [NotchInteractionCoordinator] = []

    override func tearDown() {
        coordinators.forEach { $0.stop() }
        coordinators.removeAll()
        super.tearDown()
    }

    func testHoverFromPeekOpensExpandedWhenPreferenceEnabled() async {
        let context = makeContext(hoverToOpen: true)
        context.settings.settings.openDelay = 0
        context.store.upsert(Self.sessionWithApproval())
        XCTAssertEqual(context.appState.presentation, .peeking)
        context.interaction.start()
        let expanded = expectation(description: "hover opens Peek into Expanded")
        let observation = context.appState.$presentation
            .filter { $0 == .expanded }
            .prefix(1)
            .sink { _ in expanded.fulfill() }

        let pointer = NSEvent.mouseLocation
        context.tracker.updateRects(
            compact: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20),
            expanded: .zero,
            interactive: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20)
        )
        await fulfillment(of: [expanded], timeout: 1)
        withExtendedLifetime(observation) {}

        XCTAssertEqual(context.appState.presentation, .expanded)
    }

    func testHoverOverPeekControlsDoesNotReplaceThemWithUtilities() async {
        let context = makeContext(hoverToOpen: true)
        context.settings.settings.openDelay = 0
        context.store.upsert(Self.sessionWithApproval())
        context.peek.setHoveringInteractiveControls(true)
        context.interaction.start()

        let pointer = NSEvent.mouseLocation
        context.tracker.updateRects(
            compact: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20),
            expanded: .zero,
            interactive: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20)
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(context.appState.presentation, .peeking)
    }

    func testPeekContentClickRequestOpensExpanded() {
        let context = makeContext()
        context.store.upsert(Self.sessionWithApproval())
        XCTAssertEqual(context.appState.presentation, .peeking)

        context.peek.openExpanded(face: .agents)

        XCTAssertEqual(context.appState.presentation, .expanded)
        XCTAssertEqual(context.appState.face, .agents)
    }

    func testPreparingSettingsSuspendsPeekWithoutMutatingTransaction() {
        let context = makeContext()
        let session = Self.sessionWithApproval()
        let deadline = session.approval?.actionDeadline
        context.store.upsert(session)

        context.interaction.prepareForSecondaryWindow()

        XCTAssertTrue(context.appState.isSecondaryWindowOpen)
        XCTAssertEqual(context.appState.presentation, .compact)
        XCTAssertEqual(context.store.session(id: session.id)?.approval?.requestID, "settings-transaction")
        XCTAssertEqual(context.store.session(id: session.id)?.approval?.actionDeadline, deadline)
        XCTAssertNil(context.store.session(id: session.id)?.approval?.decidedAllow)
    }

    func testClosingSettingsRestoresPeekWhenTransactionRemainsPending() {
        let context = makeContext()
        context.store.upsert(Self.sessionWithApproval())
        context.interaction.prepareForSecondaryWindow()

        context.interaction.secondaryWindowDidClose()

        XCTAssertFalse(context.appState.isSecondaryWindowOpen)
        XCTAssertEqual(context.appState.presentation, .peeking)
    }

    func testClosingSettingsRestoresCompactWhenTransactionResolved() {
        let context = makeContext()
        let session = Self.sessionWithApproval()
        context.store.upsert(session)
        context.interaction.prepareForSecondaryWindow()
        context.store.update(id: session.id) {
            $0.approval = nil
            $0.requiresAttention = false
        }

        context.interaction.secondaryWindowDidClose()

        XCTAssertFalse(context.appState.isSecondaryWindowOpen)
        XCTAssertEqual(context.appState.presentation, .compact)
    }

    func testDismissedPeekDoesNotBlockUtilitiesOrSettings() {
        let context = makeContext()
        let session = Self.sessionWithApproval()
        context.store.upsert(session)
        context.peek.dismissCurrentPeek()

        context.appState.expand(face: .utilities)
        XCTAssertEqual(context.appState.presentation, .expanded)
        XCTAssertEqual(context.appState.face, .utilities)
        context.interaction.prepareForSecondaryWindow()

        XCTAssertTrue(context.appState.isSecondaryWindowOpen)
        XCTAssertEqual(context.appState.presentation, .compact)
        XCTAssertEqual(context.store.session(id: session.id)?.approval?.requestID, "settings-transaction")
        XCTAssertNil(context.store.session(id: session.id)?.approval?.decidedAllow)
    }

    func testNavigationNeverEmitsApprovalDecision() {
        let context = makeContext()
        let session = Self.sessionWithApproval()
        context.store.upsert(session)

        context.appState.expand(face: .utilities)
        context.interaction.prepareForSecondaryWindow()
        context.interaction.secondaryWindowDidClose()
        context.appState.expand(face: .agents)

        XCTAssertEqual(context.store.session(id: session.id)?.approval?.requestID, "settings-transaction")
        XCTAssertNil(context.store.session(id: session.id)?.approval?.decidedAllow)
    }

    func testCompactClickWithoutApprovalRemainsUnchanged() {
        let context = makeContext()
        context.interaction.start()
        let pointer = NSEvent.mouseLocation
        context.tracker.updateRects(
            compact: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20),
            expanded: .zero,
            interactive: CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20)
        )
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!

        NSApp.sendEvent(event)

        XCTAssertEqual(context.appState.presentation, .expanded)
        XCTAssertEqual(context.appState.face, .utilities)
    }

    private func makeContext(
        hoverToOpen: Bool = false
    ) -> (
        settings: SettingsStore,
        appState: AppState,
        store: AgentSessionStore,
        peek: ApprovalPeekCoordinator,
        tracker: PointerTrackingService,
        interaction: NotchInteractionCoordinator
    ) {
        let settings = SettingsStore.inMemory()
        settings.settings.autoOpenOnApproval = true
        settings.settings.hoverToOpen = hoverToOpen
        let appState = AppState(settings: settings)
        let store = AgentSessionStore(fileName: "peek-navigation-\(UUID()).json")
        let peek = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        let tracker = PointerTrackingService()
        let interaction = NotchInteractionCoordinator(
            appState: appState,
            settings: settings,
            tracker: tracker,
            diagnostics: NotchDiagnostics(),
            approvalPeek: peek
        )
        coordinators.append(interaction)
        return (settings, appState, store, peek, tracker, interaction)
    }

    private static func sessionWithApproval() -> AgentSession {
        let now = Date()
        return AgentSession(
            provider: .codex,
            title: "Settings project",
            projectPath: "/tmp/settings-project",
            status: .waitingForApproval,
            requiresAttention: true,
            isManaged: false,
            isBridgeConnected: true,
            pendingApprovalRequestID: "settings-transaction",
            approval: PendingApproval(
                provider: .codex,
                sessionID: "provider-session",
                requestID: "settings-transaction",
                toolUseID: nil,
                turnID: "turn",
                rawEventName: "PermissionRequest",
                toolName: "Bash",
                summary: "printf safe",
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

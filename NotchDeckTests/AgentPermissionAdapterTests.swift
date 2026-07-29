import XCTest
import Darwin
@testable import NotchDeck

final class AgentPermissionAdapterTests: XCTestCase {
    func testClaudePermissionRequestParsingAndIdentity() throws {
        let payload: [String: Any] = [
            "session_id": "claude-session",
            "hook_event_name": "PermissionRequest",
            "cwd": "/tmp/project",
            "tool_name": "Bash",
            "tool_input": ["command": "printf test"],
        ]
        let request = try ClaudePermissionAdapter().parse(payload)
        XCTAssertEqual(request.provider, .claudeCode)
        XCTAssertEqual(request.sessionID, "claude-session")
        XCTAssertEqual(request.toolName, "Bash")
        XCTAssertEqual(request.summary, "printf test")
        XCTAssertFalse(request.requestID.isEmpty)
    }

    func testClaudeAllowDenyAndFallbackAreByteExact() {
        let adapter = ClaudePermissionAdapter()
        XCTAssertEqual(
            String(data: adapter.response(
                behavior: .allow,
                message: nil
            ), encoding: .utf8),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"# + "\n"
        )
        XCTAssertEqual(
            String(data: adapter.response(
                behavior: .deny,
                message: "Denied in NotchDeck"
            ), encoding: .utf8),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","interrupt":false,"message":"Denied in NotchDeck"},"hookEventName":"PermissionRequest"}}"# + "\n"
        )
        XCTAssertEqual(adapter.fallbackResponse(), Data())
    }

    func testCodexPermissionRequestParsingAndIdentity() throws {
        let payload: [String: Any] = [
            "session_id": "codex-session",
            "turn_id": "turn-42",
            "hook_event_name": "PermissionRequest",
            "cwd": "/tmp/project",
            "tool_name": "shell",
            "tool_input": ["command": "printf test"],
        ]
        let request = try CodexPermissionAdapter().parse(payload)
        XCTAssertEqual(request.provider, .codex)
        XCTAssertEqual(request.sessionID, "codex-session")
        XCTAssertEqual(request.turnID, "turn-42")
        XCTAssertEqual(request.summary, "printf test")
        XCTAssertTrue(request.requestID.contains("turn-42"))
    }

    func testPermissionSummaryUsesTruthfulFileAndPatchTargets() throws {
        let file = try ClaudePermissionAdapter().parse([
            "session_id": "s",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Write",
            "tool_input": ["file_path": "/tmp/project/Notes.md"],
        ])
        let patch = try CodexPermissionAdapter().parse([
            "session_id": "s",
            "turn_id": "t",
            "hook_event_name": "PermissionRequest",
            "tool_name": "apply_patch",
            "tool_input": [
                "patch": "*** Begin Patch\n*** Update File: Sources/Worker.swift\n@@\n",
            ],
        ])

        XCTAssertEqual(file.summary, "Write /tmp/project/Notes.md")
        XCTAssertEqual(patch.summary, "Apply patch to Sources/Worker.swift")
    }

    func testPermissionSummaryNamesMCPActionWithoutDumpingArguments() throws {
        let request = try ClaudePermissionAdapter().parse([
            "session_id": "s",
            "hook_event_name": "PermissionRequest",
            "tool_name": "mcp__github__create_issue",
            "tool_input": [
                "repo": "owner/project",
                "title": "Fix approval race",
                "token": "must-not-appear",
            ],
        ])

        XCTAssertEqual(request.summary, "GitHub — create issue")
        XCTAssertFalse(request.summary.contains("must-not-appear"))
    }

    func testPermissionSummaryRedactsSecretsInRealCommand() throws {
        let request = try ClaudePermissionAdapter().parse([
            "session_id": "s",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": [
                "command": "curl -H 'Authorization: Bearer abcdef1234567890' example.test",
            ],
        ])

        XCTAssertTrue(request.summary.contains("«redacted»"))
        XCTAssertFalse(request.summary.contains("abcdef1234567890"))
    }

    func testSanitizedPayloadShapeContainsKeysAndTypesButNeverValues() {
        let shape = PermissionPayloadShape.describe([
            "session_id": "session-secret",
            "tool_name": "Bash",
            "tool_input": [
                "command": "rm -rf project-secret",
                "timeout": 30,
            ],
        ])

        XCTAssertTrue(shape.contains("session_id:string"))
        XCTAssertTrue(shape.contains("tool_input:object"))
        XCTAssertTrue(shape.contains("command:string"))
        XCTAssertTrue(shape.contains("timeout:number"))
        XCTAssertFalse(shape.contains("session-secret"))
        XCTAssertFalse(shape.contains("project-secret"))
    }

    func testCodexAllowDenyAndFallbackAreByteExact() {
        let adapter = CodexPermissionAdapter()
        XCTAssertEqual(
            String(data: adapter.response(
                behavior: .allow,
                message: nil
            ), encoding: .utf8),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"# + "\n"
        )
        XCTAssertEqual(
            String(data: adapter.response(
                behavior: .deny,
                message: "Reason"
            ), encoding: .utf8),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Reason"},"hookEventName":"PermissionRequest"}}"# + "\n"
        )
        XCTAssertEqual(adapter.fallbackResponse(), Data())
    }

    func testAdaptersCannotUsePreToolUseSchema() {
        for bytes in [
            ClaudePermissionAdapter().response(behavior: .allow, message: nil),
            CodexPermissionAdapter().response(behavior: .allow, message: nil),
        ] {
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertTrue(text.contains(#""hookEventName":"PermissionRequest""#))
            XCTAssertFalse(text.contains("permissionDecision"))
            XCTAssertFalse(text.contains("PreToolUse"))
        }
    }

    func testCodexIdentitySeparatesConcurrentTurns() throws {
        let adapter = CodexPermissionAdapter()
        let first = try adapter.parse([
            "session_id": "s", "turn_id": "turn-1",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": ["command": "same"],
        ])
        let second = try adapter.parse([
            "session_id": "s", "turn_id": "turn-2",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": ["command": "same"],
        ])
        XCTAssertNotEqual(first.requestID, second.requestID)
    }

    func testStableInputHashIgnoresDictionaryOrder() throws {
        let adapter = CodexPermissionAdapter()
        let a = try adapter.parse([
            "session_id": "s", "turn_id": "t",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": ["a": 1, "b": 2],
        ])
        let b = try adapter.parse([
            "session_id": "s", "turn_id": "t",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": ["b": 2, "a": 1],
        ])
        XCTAssertEqual(a.requestID, b.requestID)
    }

    func testPrimitiveToolInputsRemainDistinct() throws {
        let adapter = CodexPermissionAdapter()
        let a = try adapter.parse([
            "session_id": "s", "turn_id": "t",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": "first",
        ])
        let b = try adapter.parse([
            "session_id": "s", "turn_id": "t",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell", "tool_input": "second",
        ])
        XCTAssertNotEqual(a.requestID, b.requestID)
    }

    func testPermissionRequestCreatesApprovalAndPreToolUseDoesNot() {
        let id = UUID()
        let permission = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 0,
            turnID: "t",
            toolName: "shell",
            requestID: "s|t"
        )
        let state = TerminalAgentBridge.reduce(existing: nil, id: id, event: permission)
        XCTAssertEqual(state.approval?.rawEventName, "PermissionRequest")
        XCTAssertEqual(state.approval?.requestID, "s|t")

        let preToolUse = TerminalAgentEvent(
            type: .toolPermissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 0,
            requestID: "legacy"
        )
        XCTAssertNil(TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: preToolUse
        ).approval)
    }

    func testTerminalOnlyNeverCreatesDecisionUI() {
        let event = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 0,
            turnID: "t",
            requestID: "s|t"
        )
        let state = TerminalAgentBridge.reduce(
            existing: nil,
            id: UUID(),
            event: event,
            handlingMode: .terminalOnly
        )
        XCTAssertNil(state.approval)
        XCTAssertFalse(state.requiresAttention)
        XCTAssertEqual(state.latestSummary, "Respond in Terminal")
    }

    func testProgressionRequiresMatchingProviderIdentity() {
        let approval = PendingApproval(
            provider: .codex,
            sessionID: "s",
            requestID: "s|turn-1",
            toolUseID: nil,
            turnID: "turn-1",
            rawEventName: "PermissionRequest",
            toolName: "shell",
            summary: "Permission requested",
            receivedAt: Date(),
            expiresAt: Date().addingTimeInterval(30),
            state: .sent,
            handlingMode: .notchOnly,
            fallbackDeadline: nil,
            nativePromptExpected: false
        )
        XCTAssertTrue(TerminalAgentBridge.providerProgressMatches(
            approval,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .codex,
                                      sessionID: "s", timestamp: 1, turnID: "turn-1")
        ))
        XCTAssertFalse(TerminalAgentBridge.providerProgressMatches(
            approval,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .codex,
                                      sessionID: "s", timestamp: 1, turnID: "turn-2")
        ))
        XCTAssertFalse(TerminalAgentBridge.providerProgressMatches(
            approval,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .codex,
                                      sessionID: "s", timestamp: 1)
        ))
    }

    func testConcurrentRequestsRemainQueuedAndDistinct() {
        let id = UUID()
        let firstEvent = TerminalAgentEvent(
            type: .permissionRequested, provider: .codex, sessionID: "s",
            timestamp: 1, turnID: "turn-1", requestID: "s|turn-1"
        )
        let secondEvent = TerminalAgentEvent(
            type: .permissionRequested, provider: .codex, sessionID: "s",
            timestamp: 2, turnID: "turn-2", requestID: "s|turn-2"
        )
        let first = TerminalAgentBridge.reduce(existing: nil, id: id, event: firstEvent)
        let both = TerminalAgentBridge.reduce(existing: first, id: id, event: secondEvent)
        XCTAssertEqual(both.approval?.requestID, "s|turn-1")
        XCTAssertEqual(both.queuedApprovals?.map(\.requestID), ["s|turn-2"])

        let duplicate = TerminalAgentBridge.reduce(existing: both, id: id, event: secondEvent)
        XCTAssertEqual(duplicate.queuedApprovalCount, 1)

        let unrelated = TerminalAgentBridge.reduce(
            existing: duplicate,
            id: id,
            event: TerminalAgentEvent(type: .toolCompleted, provider: .codex,
                                      sessionID: "s", timestamp: 3, turnID: "other")
        )
        XCTAssertEqual(unrelated.approval?.requestID, "s|turn-1")
        XCTAssertEqual(unrelated.queuedApprovals?.map(\.requestID), ["s|turn-2"])
    }

    func testRequestAfterHelperExitedPromotesInsteadOfBlockingBehindTerminalState() {
        let id = UUID()
        let firstEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 1,
            turnID: "turn-1",
            requestID: "native-1",
            transactionID: "transaction-1"
        )
        let secondEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 2,
            turnID: "turn-2",
            requestID: "native-2",
            transactionID: "transaction-2"
        )

        var first = TerminalAgentBridge.reduce(existing: nil, id: id, event: firstEvent)
        first.approval?.state = .helperExited
        first.approval?.decidedAllow = false

        let next = TerminalAgentBridge.reduce(existing: first, id: id, event: secondEvent)

        XCTAssertEqual(next.approval?.requestID, "transaction-2")
        XCTAssertEqual(next.approval?.state, .pending)
        XCTAssertNil(next.queuedApprovals)
        XCTAssertTrue(next.requiresAttention)
    }

    func testTerminalResolutionOfExpiredHeadAdvancesPeekQueue() {
        let id = UUID()
        let firstEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 1,
            turnID: "turn-1",
            requestID: "native-1",
            transactionID: "transaction-1"
        )
        let secondEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 2,
            turnID: "turn-2",
            requestID: "native-2",
            transactionID: "transaction-2"
        )
        let t0 = Date(timeIntervalSince1970: 1_000)
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: id,
            event: firstEvent,
            approvalLifetime: 30,
            now: t0
        )
        session = TerminalAgentBridge.reduce(
            existing: session,
            id: id,
            event: secondEvent,
            approvalLifetime: 300,
            now: t0.addingTimeInterval(1)
        )
        _ = TerminalAgentBridge.expireTransactions(
            &session,
            now: t0.addingTimeInterval(31)
        )
        XCTAssertEqual(session.approval?.state, .fellBack)

        let resolved = TerminalAgentBridge.reduce(
            existing: session,
            id: id,
            event: TerminalAgentEvent(
                type: .toolCompleted,
                provider: .codex,
                sessionID: "s",
                timestamp: 40,
                turnID: "turn-1"
            ),
            now: t0.addingTimeInterval(31)
        )

        XCTAssertEqual(resolved.approval?.requestID, "transaction-2")
        XCTAssertNil(resolved.queuedApprovals)
    }

    func testTerminalResolutionRemovesMatchingQueuedPeekTransaction() {
        let id = UUID()
        let firstEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 1,
            turnID: "turn-1",
            requestID: "native-1",
            transactionID: "transaction-1"
        )
        let secondEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 2,
            turnID: "turn-2",
            requestID: "native-2",
            transactionID: "transaction-2"
        )
        var session = TerminalAgentBridge.reduce(existing: nil, id: id, event: firstEvent)
        session = TerminalAgentBridge.reduce(existing: session, id: id, event: secondEvent)

        let resolved = TerminalAgentBridge.reduce(
            existing: session,
            id: id,
            event: TerminalAgentEvent(
                type: .toolCompleted,
                provider: .codex,
                sessionID: "s",
                timestamp: 3,
                turnID: "turn-2"
            )
        )

        XCTAssertEqual(resolved.approval?.requestID, "transaction-1")
        XCTAssertNil(resolved.queuedApprovals)
    }

    func testUnrelatedQueuedTerminalResolutionDoesNotClearExpiredHead() {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let firstEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 1,
            turnID: "turn-1",
            requestID: "native-1",
            transactionID: "transaction-1"
        )
        let secondEvent = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "s",
            timestamp: 2,
            turnID: "turn-2",
            requestID: "native-2",
            transactionID: "transaction-2"
        )
        var session = TerminalAgentBridge.reduce(
            existing: nil,
            id: id,
            event: firstEvent,
            approvalLifetime: 30,
            now: t0
        )
        session = TerminalAgentBridge.reduce(
            existing: session,
            id: id,
            event: secondEvent,
            approvalLifetime: 300,
            now: t0.addingTimeInterval(1)
        )
        _ = TerminalAgentBridge.expireTransactions(
            &session,
            now: t0.addingTimeInterval(31)
        )

        let resolved = TerminalAgentBridge.reduce(
            existing: session,
            id: id,
            event: TerminalAgentEvent(
                type: .toolCompleted,
                provider: .codex,
                sessionID: "s",
                timestamp: 40,
                turnID: "turn-2"
            ),
            now: t0.addingTimeInterval(31)
        )

        XCTAssertEqual(resolved.approval?.requestID, "transaction-1")
        XCTAssertEqual(resolved.approval?.state, .fellBack)
        XCTAssertNil(resolved.queuedApprovals)
    }

    func testIdenticalProviderRequestIDsUseIndependentHelperTransactions() {
        let first = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "session-a",
            timestamp: 1,
            turnID: "same-turn",
            requestID: "native-shared",
            transactionID: "transaction-a"
        )
        let second = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "session-b",
            timestamp: 1,
            turnID: "same-turn",
            requestID: "native-shared",
            transactionID: "transaction-b"
        )
        let a = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: first)
        let b = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: second)
        XCTAssertEqual(a.approval?.requestID, "transaction-a")
        XCTAssertEqual(b.approval?.requestID, "transaction-b")
        XCTAssertEqual(a.approval?.providerRequestID, "native-shared")
        XCTAssertEqual(b.approval?.providerRequestID, "native-shared")
    }

    @MainActor
    func testBridgeRoutesSameNativeIDToExactTransactionSocket() async throws {
        var firstPair = [Int32](repeating: -1, count: 2)
        var secondPair = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &firstPair), 0)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &secondPair), 0)
        defer {
            firstPair.forEach { if $0 >= 0 { close($0) } }
            secondPair.forEach { if $0 >= 0 { close($0) } }
        }

        let bridge = TerminalAgentBridge(
            store: AgentSessionStore(fileName: "routing-\(UUID().uuidString).json"),
            stats: TerminalBridgeStats()
        )
        await bridge.registerPendingForTesting(
            transactionID: "transaction-a",
            providerRequestID: "native-shared",
            appSessionID: UUID(),
            clientFD: firstPair[0]
        )
        await bridge.registerPendingForTesting(
            transactionID: "transaction-b",
            providerRequestID: "native-shared",
            appSessionID: UUID(),
            clientFD: secondPair[0]
        )

        let firstDelivered = await bridge.respond(
            requestID: "transaction-a",
            allow: true,
            message: nil
        )
        XCTAssertTrue(firstDelivered)
        let firstDecision = try readDecision(from: firstPair[1])
        XCTAssertEqual(firstDecision.transactionID, "transaction-a")
        XCTAssertEqual(firstDecision.requestID, "native-shared")

        var secondPoll = pollfd(fd: secondPair[1], events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&secondPoll, 1, 0), 0, "session B received session A's decision")

        let secondDelivered = await bridge.respond(
            requestID: "transaction-b",
            allow: false,
            message: "Denied"
        )
        XCTAssertTrue(secondDelivered)
        let secondDecision = try readDecision(from: secondPair[1])
        XCTAssertEqual(secondDecision.transactionID, "transaction-b")
        XCTAssertEqual(secondDecision.requestID, "native-shared")
        XCTAssertEqual(secondDecision.behavior, .deny)
    }

    @MainActor
    func testDisablingAgentsImmediatelyReleasesPendingHelper() async throws {
        var pair = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { pair.forEach { if $0 >= 0 { close($0) } } }

        let store = AgentSessionStore(fileName: "disable-release-\(UUID().uuidString).json")
        let sessionID = UUID()
        let event = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "provider-session",
            timestamp: 1,
            turnID: "turn",
            requestID: "native",
            transactionID: "transaction"
        )
        store.upsert(TerminalAgentBridge.reduce(existing: nil, id: sessionID, event: event))
        let bridge = TerminalAgentBridge(store: store, stats: TerminalBridgeStats())
        await bridge.registerPendingForTesting(
            transactionID: "transaction",
            providerRequestID: "native",
            appSessionID: sessionID,
            clientFD: pair[0]
        )

        await bridge.setUIAvailable(false)

        let release = try readDecision(from: pair[1])
        XCTAssertTrue(release.fallback)
        XCTAssertEqual(release.transactionID, "transaction")
        XCTAssertEqual(store.session(id: sessionID)?.approval?.state, .fellBack)
        XCTAssertEqual(store.session(id: sessionID)?.latestSummary, "Respond in Terminal")
    }

    @MainActor
    func testPeekAllowResolvesExactTransactionOnlyOnce() async throws {
        var pair = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { pair.forEach { if $0 >= 0 { close($0) } } }

        let store = AgentSessionStore(fileName: "peek-allow-\(UUID().uuidString).json")
        let sessionID = UUID()
        let event = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .claudeCode,
            sessionID: "provider-session",
            timestamp: 1,
            toolName: "Bash",
            requestID: "native",
            transactionID: "transaction"
        )
        store.upsert(TerminalAgentBridge.reduce(existing: nil, id: sessionID, event: event))
        let bridge = TerminalAgentBridge(store: store, stats: TerminalBridgeStats())
        await bridge.registerPendingForTesting(
            transactionID: "transaction",
            providerRequestID: "native",
            appSessionID: sessionID,
            clientFD: pair[0]
        )
        let coordinator = AgentCoordinator(
            store: store,
            settings: SettingsStore(defaults: UserDefaults(
                suiteName: "peek-allow-\(UUID().uuidString)"
            )!),
            providers: [:]
        )
        coordinator.terminalBridge = bridge

        let firstAllow = await coordinator.decide(
            sessionID: sessionID,
            transactionID: "transaction",
            allow: true
        )
        let duplicateAllow = await coordinator.decide(
            sessionID: sessionID,
            transactionID: "transaction",
            allow: true
        )
        XCTAssertTrue(firstAllow)
        XCTAssertFalse(duplicateAllow)

        let decision = try readDecision(from: pair[1])
        XCTAssertEqual(decision.transactionID, "transaction")
        XCTAssertEqual(decision.behavior, .allow)
        var duplicatePoll = pollfd(fd: pair[1], events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&duplicatePoll, 1, 0), 0)
    }

    @MainActor
    func testPeekDenyResolvesExactTransactionOnlyOnce() async throws {
        var pair = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { pair.forEach { if $0 >= 0 { close($0) } } }

        let store = AgentSessionStore(fileName: "peek-deny-\(UUID().uuidString).json")
        let sessionID = UUID()
        let event = TerminalAgentEvent(
            type: .permissionRequested,
            provider: .codex,
            sessionID: "provider-session",
            timestamp: 1,
            turnID: "turn",
            toolName: "shell",
            requestID: "native",
            transactionID: "transaction"
        )
        store.upsert(TerminalAgentBridge.reduce(existing: nil, id: sessionID, event: event))
        let bridge = TerminalAgentBridge(store: store, stats: TerminalBridgeStats())
        await bridge.registerPendingForTesting(
            transactionID: "transaction",
            providerRequestID: "native",
            appSessionID: sessionID,
            clientFD: pair[0]
        )
        let coordinator = AgentCoordinator(
            store: store,
            settings: SettingsStore(defaults: UserDefaults(
                suiteName: "peek-deny-\(UUID().uuidString)"
            )!),
            providers: [:]
        )
        coordinator.terminalBridge = bridge

        let firstDeny = await coordinator.decide(
            sessionID: sessionID,
            transactionID: "transaction",
            allow: false
        )
        let duplicateDeny = await coordinator.decide(
            sessionID: sessionID,
            transactionID: "transaction",
            allow: false
        )
        XCTAssertTrue(firstDeny)
        XCTAssertFalse(duplicateDeny)

        let decision = try readDecision(from: pair[1])
        XCTAssertEqual(decision.transactionID, "transaction")
        XCTAssertEqual(decision.behavior, .deny)
        var duplicatePoll = pollfd(fd: pair[1], events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&duplicatePoll, 1, 0), 0)
    }

    @MainActor
    func testLatePeekClickIsRejectedWithoutRecordingDecision() async {
        let store = AgentSessionStore(fileName: "peek-late-\(UUID().uuidString).json")
        let sessionID = UUID()
        let expiredAt = Date(timeIntervalSince1970: 100)
        var session = AgentSession(
            id: sessionID,
            provider: .claudeCode,
            title: "Expired",
            projectPath: "/tmp",
            status: .waitingForApproval,
            isManaged: false,
            isBridgeConnected: true,
            pendingApprovalRequestID: "transaction"
        )
        session.approval = PendingApproval(
            provider: .claudeCode,
            sessionID: "provider-session",
            requestID: "transaction",
            rawEventName: "PermissionRequest",
            toolName: "Bash",
            summary: "printf safe",
            receivedAt: expiredAt.addingTimeInterval(-60),
            expiresAt: expiredAt,
            state: .pending,
            handlingMode: .notchWithTerminalFallback,
            fallbackDeadline: expiredAt,
            nativePromptExpected: true
        )
        store.upsert(session)
        let coordinator = AgentCoordinator(
            store: store,
            settings: SettingsStore(defaults: UserDefaults(
                suiteName: "peek-late-\(UUID().uuidString)"
            )!),
            providers: [:]
        )

        let accepted = await coordinator.decide(
            sessionID: sessionID,
            transactionID: "transaction",
            allow: true,
            now: expiredAt
        )
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.session(id: sessionID)?.approval?.state, .pending)
        XCTAssertNil(store.session(id: sessionID)?.approval?.decidedAllow)
    }

    private func readDecision(from fd: Int32) throws -> TerminalAgentDecision {
        var data = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1, byte != 0x0A {
            data.append(byte)
        }
        return try XCTUnwrap(
            TerminalAgentCodec.decodeDecision(String(decoding: data, as: UTF8.self))
        )
    }

    func testCodexTrustRequiresReviewedPermissionRequestCommand() {
        XCTAssertEqual(
            HookInstaller.codexTrustStatus(configText: ""),
            .approvalRequired
        )
        XCTAssertEqual(
            HookInstaller.codexTrustStatus(configText: """
            [hooks.state]
            ":pre_tool_use:notchdeck-agent-hook" = "reviewed"
            """),
            .approvalRequired
        )
        XCTAssertEqual(
            HookInstaller.codexTrustStatus(configText: """
            [hooks.state]
            ":permission_request:notchdeck-agent-hook" = "reviewed"
            """),
            .reviewed
        )
    }

    func testIntegrationStateSeparatesMissingTrustAndObservedWorking() {
        XCTAssertEqual(
            HookInstaller.integrationState(
                provider: .codex,
                installed: false,
                trustStatus: .reviewed,
                observedEvent: true
            ),
            .hooksMissing
        )
        XCTAssertEqual(
            HookInstaller.integrationState(
                provider: .codex,
                installed: true,
                trustStatus: .approvalRequired,
                observedEvent: false
            ),
            .trustRequired
        )
        XCTAssertEqual(
            HookInstaller.integrationState(
                provider: .codex,
                installed: true,
                trustStatus: .approvalRequired,
                observedEvent: true
            ),
            .working
        )
        XCTAssertEqual(
            HookInstaller.integrationState(
                provider: .claudeCode,
                installed: true,
                trustStatus: .notApplicable,
                observedEvent: false
            ),
            .working
        )
    }
}

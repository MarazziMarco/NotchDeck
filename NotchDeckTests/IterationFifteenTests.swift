import XCTest
@testable import NotchDeck

// MARK: Approval classification

final class ApprovalClassificationTests: XCTestCase {
    private func event(_ type: TerminalAgentEventType, provider: TerminalAgentProvider = .claudeCode,
                       requestID: String? = nil, tool: String? = nil,
                       turnID: String? = nil) -> TerminalAgentEvent {
        TerminalAgentEvent(type: type, provider: provider, sessionID: "S1", cwd: "/tmp/proj",
                           timestamp: 1000, turnID: turnID, toolName: tool,
                           summary: tool.map { "run \($0)" },
                           requestID: requestID)
    }

    func testClaudePreToolUseNeverCreatesApproval() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: event(.toolStarted, tool: "Bash"))
        XCTAssertNil(s.approval)
        XCTAssertNotEqual(s.status, .waitingForApproval)
        XCTAssertEqual(s.status, .running)
    }
    func testCodexPreToolUseNeverCreatesApproval() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: event(.toolStarted, provider: .codex, tool: "shell"))
        XCTAssertNil(s.approval)
        XCTAssertEqual(s.status, .running)
    }
    func testPermissionRequestCreatesOneApproval() {
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(),
                                           event: event(.permissionRequested, requestID: "R1", tool: "Bash"))
        XCTAssertNotNil(s.approval)
        XCTAssertEqual(s.approval?.state, .pending)
        XCTAssertEqual(s.approval?.rawEventName, "PermissionRequest")
        XCTAssertEqual(s.status, .waitingForApproval)
    }
    func testDuplicatePermissionRequestNoDuplicate() {
        let id = UUID()
        let first = TerminalAgentBridge.reduce(existing: nil, id: id,
                                               event: event(.permissionRequested, requestID: "R1"), now: Date(timeIntervalSince1970: 1))
        let second = TerminalAgentBridge.reduce(existing: first, id: id,
                                                event: event(.permissionRequested, requestID: "R1"), now: Date(timeIntervalSince1970: 99))
        XCTAssertEqual(first.approval?.receivedAt, second.approval?.receivedAt) // same approval, not recreated
    }
    func testPostToolUseClearsApproval() {
        let id = UUID()
        let approved = TerminalAgentBridge.reduce(
            existing: nil, id: id,
            event: event(.permissionRequested, requestID: "R1", turnID: "turn-1"))
        let after = TerminalAgentBridge.reduce(
            existing: approved, id: id,
            event: event(.toolCompleted, turnID: "turn-1"))
        XCTAssertNil(after.approval)
        XCTAssertFalse(after.requiresAttention)
    }
    func testStopAndSessionEndClearApproval() {
        let id = UUID()
        let approved = TerminalAgentBridge.reduce(existing: nil, id: id, event: event(.permissionRequested, requestID: "R1"))
        XCTAssertNil(TerminalAgentBridge.reduce(existing: approved, id: id, event: event(.agentStopped)).approval)
        XCTAssertNil(TerminalAgentBridge.reduce(existing: approved, id: id, event: event(.sessionEnded)).approval)
    }
    func testClassifierRules() {
        XCTAssertTrue(ApprovalClassifier.createsApproval(.permissionRequested))
        XCTAssertFalse(ApprovalClassifier.createsApproval(.toolPermissionRequested))
        XCTAssertFalse(ApprovalClassifier.createsApproval(.toolStarted))
        XCTAssertTrue(ApprovalClassifier.clearsApproval(.toolCompleted))
        XCTAssertTrue(ApprovalClassifier.clearsApproval(.agentStopped))
        XCTAssertTrue(ApprovalClassifier.clearsApproval(.sessionEnded))
        XCTAssertFalse(ApprovalClassifier.clearsApproval(.toolStarted))
    }
}

// MARK: Permission handling modes

final class PermissionHandlingModeTests: XCTestCase {
    // The card's actionable deadline is now the mirrored approval LIFETIME (not the
    // old terminal-fallback delay). Tests pass an explicit lifetime.
    private func perm(mode: AgentPermissionHandlingMode, delay: TimeInterval = 8,
                      lifetime: TimeInterval = 60,
                      now: Date = Date(timeIntervalSince1970: 1000)) -> AgentSession {
        let e = TerminalAgentEvent(type: .permissionRequested, provider: .claudeCode,
                                   sessionID: "S", cwd: "/p", timestamp: 1000, requestID: "R1")
        return TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: e,
                                          handlingMode: mode, fallbackDelay: delay,
                                          approvalLifetime: lifetime, now: now)
    }

    func testTerminalOnlyHasNoFunctionalDecision() {
        XCTAssertFalse(AgentPermissionHandlingMode.terminalOnly.showsFunctionalDecision)
        let s = perm(mode: .terminalOnly)
        XCTAssertNil(s.approval)
        XCTAssertFalse(s.requiresAttention)
        XCTAssertEqual(s.latestSummary, "Respond in Terminal")
    }
    func testNotchOnlyExpectsNoNativePrompt() {
        XCTAssertTrue(AgentPermissionHandlingMode.notchOnly.showsFunctionalDecision)
        let s = perm(mode: .notchOnly)
        XCTAssertNil(s.approval?.fallbackDeadline)
        XCTAssertFalse(s.approval?.nativePromptExpected == true)
    }
    func testHybridSetsLifetimeDeadline() {
        let now = Date(timeIntervalSince1970: 1000)
        let s = perm(mode: .notchWithTerminalFallback, lifetime: 8, now: now)
        XCTAssertEqual(s.approval?.fallbackDeadline, now.addingTimeInterval(8))
        XCTAssertTrue(s.approval?.nativePromptExpected == true)
    }
    func testHybridAnsweredBeforeDeadlineStillLive() {
        let now = Date(timeIntervalSince1970: 1000)
        let s = perm(mode: .notchWithTerminalFallback, lifetime: 8, now: now)
        XCTAssertEqual(s.approval?.fallbackRemaining(now: now), 8)
        XCTAssertGreaterThan(s.approval!.fallbackRemaining(now: now.addingTimeInterval(3))!, 0)
    }
    func testHybridAfterDeadlineFallbackElapsed() {
        let now = Date(timeIntervalSince1970: 1000)
        let s = perm(mode: .notchWithTerminalFallback, lifetime: 8, now: now)
        XCTAssertEqual(s.approval?.fallbackRemaining(now: now.addingTimeInterval(20)), 0)
    }
    func testNoModeAutoApproves() {
        for mode in AgentPermissionHandlingMode.allCases {
            let s = perm(mode: mode)
            if mode == .terminalOnly {
                XCTAssertEqual(s.status, .running)
                XCTAssertNil(s.approval)
            } else {
                XCTAssertEqual(s.status, .waitingForApproval)
                XCTAssertNotNil(s.approval)
            }
        }
    }
    func testTimeoutFailsSafeNeverApproves() {
        let now = Date(timeIntervalSince1970: 1000)
        let s = perm(mode: .notchOnly, now: now)
        XCTAssertTrue(s.approval!.isExpired(now: now.addingTimeInterval(130)))  // >120s hard expiry
        XCTAssertFalse(s.approval!.isExpired(now: now.addingTimeInterval(10)))
    }
    func testFallbackDelayOptions() {
        XCTAssertEqual(TerminalFallbackDelay.s8.seconds, 8)
        XCTAssertEqual(AppSettings().terminalFallbackDelay, .s8)
        XCTAssertEqual(AppSettings().agentPermissionHandlingMode, .notchWithTerminalFallback)
    }
}

// MARK: Provider appearance

final class ProviderAppearanceTests: XCTestCase {
    func testClaudeResolvesToSuppliedAsset() {
        let a = AgentProviderAppearanceRegistry.appearance(.claudeCode)
        XCTAssertEqual(a.assetLight, "AgentLogoClaudeLight")
        XCTAssertEqual(a.assetDark, "AgentLogoClaudeDark")
        XCTAssertEqual(a.displayName, "Claude Code")
    }
    func testCodexResolvesToSuppliedAsset() {
        let a = AgentProviderAppearanceRegistry.appearance(.codex)
        XCTAssertEqual(a.assetLight, "AgentLogoCodexLight")
        XCTAssertEqual(a.assetDark, "AgentLogoCodexDark")
    }
    func testGeminiResolvesToSuppliedAsset() {
        XCTAssertEqual(AgentProviderAppearanceRegistry.appearance(.gemini).assetLight, "AgentLogoGemini")
    }
    func testDarkBackgroundSelectsWhiteLogo() {
        let claude = AgentProviderAppearanceRegistry.appearance(.claudeCode)
        XCTAssertEqual(claude.assetName(darkBackground: true), "AgentLogoClaudeLight")   // white on dark
        XCTAssertEqual(claude.assetName(darkBackground: false), "AgentLogoClaudeDark")   // black on light
    }
    func testUnknownFallsBackToMonogramNotSparkle() {
        let a = AgentProviderAppearanceRegistry.appearance(.unknown)
        XCTAssertNil(a.assetLight)
        XCTAssertEqual(a.monogram, "»_")
        XCTAssertNotEqual(a.fallbackSymbol, "sparkle")
    }
    func testMonogramsAreDistinct() {
        XCTAssertEqual(AgentVendor.claudeCode.monogram, "C")
        XCTAssertEqual(AgentVendor.codex.monogram, "CX")
        XCTAssertEqual(AgentVendor.gemini.monogram, "G")
        XCTAssertEqual(AgentVendor.copilot.monogram, "CP")
        XCTAssertEqual(AgentVendor.cursor.monogram, "CR")
        XCTAssertEqual(AgentVendor.aider.monogram, "A")
        XCTAssertEqual(AgentVendor.opencode.monogram, "OC")
    }
    func testVendorResolutionFromExternalHint() {
        XCTAssertEqual(AgentVendor.resolve(kind: .external, hint: "gemini - myproj"), .gemini)
        XCTAssertEqual(AgentVendor.resolve(kind: .external, hint: "aider chat"), .aider)
        XCTAssertEqual(AgentVendor.resolve(kind: .external, hint: "zsh"), .unknown)
        XCTAssertEqual(AgentVendor.resolve(kind: .claudeCode, hint: nil), .claudeCode)
    }
}

// MARK: Latest message resolution & sanitisation

final class LatestMessageTests: XCTestCase {
    func testSourcePriority() {
        let r = AgentLatestMessage.resolve(lastAssistantMessage: "hello there",
                                           eventSummary: "sum", toolAction: "tool", transcriptTail: "tail",
                                           status: .running)
        XCTAssertEqual(r, "hello there")
    }
    func testFallsThroughToStatus() {
        let r = AgentLatestMessage.resolve(lastAssistantMessage: nil, eventSummary: nil,
                                           toolAction: nil, transcriptTail: nil, status: .completed)
        XCTAssertEqual(r, AgentSessionStatus.completed.label)
    }
    func testSanitizeStripsSecretsAndEscapeCodes() {
        let raw = "\u{1B}[31mrunning\u{1B}[0m with sk-ABCDEF123456 token"
        let s = AgentLatestMessage.sanitize(raw)
        XCTAssertFalse(s.contains("sk-ABCDEF123456"))
        XCTAssertFalse(s.contains("\u{1B}"))
        XCTAssertTrue(s.contains("•••"))
    }
    func testSanitizeDropsRawJSON() {
        XCTAssertEqual(AgentLatestMessage.sanitize("{\"tool\":\"Bash\"}"), "")
    }
    func testLengthCap() {
        let long = String(repeating: "a", count: 900)
        XCTAssertLessThanOrEqual(AgentLatestMessage.sanitize(long).count, AgentLatestMessage.maxChars)
    }
    func testTranscriptTailGracefulOnMissing() {
        XCTAssertNil(AgentTranscript.tail(path: "/nonexistent/notch-\(UUID()).jsonl"))
        // resolve still yields a graceful fallback
        XCTAssertEqual(AgentLatestMessage.resolve(lastAssistantMessage: nil, eventSummary: nil,
                                                  toolAction: nil, transcriptTail: nil, status: .running),
                       AgentSessionStatus.running.label)
    }
}

// MARK: Compact activity

final class CompactAgentsTests: XCTestCase {
    func testDefaultIsActiveCountNotElapsed() {
        XCTAssertEqual(AppSettings().compactAgentsDisplay, .activeCount)
        XCTAssertEqual(AppSettings().agentCompactAccent, .orange)
    }
    func testSingleActiveIsProviderNeutral() {
        let model = CompactAgentIndicatorModel.resolve(
            CompactAgentIndicatorInputs(activeSessionCount: 1)
        )
        XCTAssertEqual(model, .activeSessions(count: 1))
        XCTAssertFalse(model.accessibilityLabel.contains("Claude"))
    }
    func testMultipleActiveUsesOneAggregate() {
        let model = CompactAgentIndicatorModel.resolve(
            CompactAgentIndicatorInputs(activeSessionCount: 3)
        )
        XCTAssertEqual(model, .activeSessions(count: 3))
        XCTAssertEqual(model.compactCountText, "3")
    }
    func testApprovalTakesPriority() {
        let model = CompactAgentIndicatorModel.resolve(
            CompactAgentIndicatorInputs(
                activeSessionCount: 2,
                pendingApprovalCount: 1,
                inputRequiredCount: 1
            )
        )
        XCTAssertEqual(model, .approvalRequired(count: 1))
    }
    func testHiddenDisplaySuppressesActive() {
        XCTAssertEqual(
            CompactAgentIndicatorModel.resolve(
                CompactAgentIndicatorInputs(
                    activeSessionCount: 1,
                    displayPreference: .hidden
                )
            ),
            .hidden
        )
    }
}

// MARK: Active / Recent bucketing & liveness

final class AgentBucketingTests: XCTestCase {
    private func session(_ status: AgentSessionStatus, bridge: Bool = true, external: Bool = false) -> AgentSession {
        var s = AgentSession(provider: .claudeCode, title: "t", projectPath: "/p", status: status, isManaged: false)
        s.isBridgeConnected = bridge
        if external { s.externalBundleID = "com.apple.Terminal" }
        return s
    }

    // Presence-driven bucketing: terminal existence, NOT activity/approval.
    func testCompletedWithTabOpenStaysActive() {
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .present, status: .completed,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .active)
    }
    func testRunningPresentIsActive() {
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .present, status: .running,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .active)
    }
    func testTerminalMissingMovesToRecent() {
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .missing, status: .running,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .recent)
    }
    func testUnknownConnectedStaysActive() {
        XCTAssertEqual(AgentSessionFilter.bucket(presence: .unknown, status: .idle,
                                                 isBridgeConnected: true, isManaged: false,
                                                 hasExternalWindow: false), .active)
    }

    @MainActor func testStoreCompletedButTabOpenIsActive() {
        let store = AgentSessionStore(fileName: "test-active-\(UUID()).json")
        var s = session(.completed); s.terminalPresence = .present
        store.upsert(s)
        XCTAssertEqual(store.activeSessions.count, 1)   // completed + tab open → Active
        XCTAssertTrue(store.recentSessions.isEmpty)
    }
    @MainActor func testRecentRespectsLimit() {
        let store = AgentSessionStore(fileName: "test-recent-\(UUID()).json")
        store.recentLimit = .five
        for _ in 0..<8 {
            var s = session(.completed); s.terminalPresence = .missing
            store.upsert(s)
        }
        XCTAssertEqual(store.recentSessions.count, 5)
    }
    @MainActor func testRecentOffHidesAll() {
        let store = AgentSessionStore(fileName: "test-off-\(UUID()).json")
        store.recentLimit = .off
        var s = session(.completed); s.terminalPresence = .missing
        store.upsert(s)
        XCTAssertTrue(store.recentSessions.isEmpty)
    }
    @MainActor func testClosedTerminalNotInActive() {
        let store = AgentSessionStore(fileName: "test-closed-\(UUID()).json")
        var s = session(.running); s.terminalPresence = .missing
        store.upsert(s)
        XCTAssertTrue(store.activeSessions.isEmpty)   // terminal gone → Recent, not Active
    }
}

// MARK: External/connected merge

final class AgentMergeTests: XCTestCase {
    func testMergeByPID() {
        var ext = AgentSession(provider: .external, title: "claude", projectPath: "", isManaged: false)
        ext.pid = 4242; ext.externalWindowTitle = "claude"
        var conn = AgentSession(provider: .claudeCode, title: "proj", projectPath: "/x/proj", isManaged: false)
        conn.pid = 4242; conn.isBridgeConnected = true
        XCTAssertTrue(AgentSessionMerge.externalDuplicatesConnected(external: ext, connected: conn))
    }
    func testMergeByProjectTitle() {
        var ext = AgentSession(provider: .external, title: "myproj — claude", projectPath: "", isManaged: false)
        ext.externalWindowTitle = "myproj — claude"
        let conn = AgentSession(provider: .claudeCode, title: "myproj", projectPath: "/x/myproj",
                                isManaged: false)
        XCTAssertTrue(AgentSessionMerge.externalDuplicatesConnected(external: ext, connected: conn))
    }
    func testNoFalseMerge() {
        let ext = AgentSession(provider: .external, title: "other", projectPath: "", isManaged: false)
        let conn = AgentSession(provider: .claudeCode, title: "proj", projectPath: "/x/proj", isManaged: false)
        XCTAssertFalse(AgentSessionMerge.externalDuplicatesConnected(external: ext, connected: conn))
    }
}

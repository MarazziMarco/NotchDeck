import XCTest
@testable import NotchDeck

final class AgentProcessDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        pid: Int32 = 100,
        seconds: UInt64 = 10,
        micros: UInt64 = 20,
        parentPID: Int32 = 1,
        provider: AgentProviderKind = .claudeCode,
        classification: AgentProviderClassification? = nil,
        tty: String? = "/dev/ttys003",
        cwd: String? = "/tmp/project"
    ) -> AgentProcessSnapshot {
        AgentProcessSnapshot(
            identity: AgentProcessIdentity(
                pid: pid,
                startSeconds: seconds,
                startMicroseconds: micros
            ),
            parentPID: parentPID,
            provider: provider,
            classification: classification ?? (provider == .codex ? .nativeCodex : .nativeClaude),
            executableBasename: provider == .codex ? "codex" : "claude",
            workingDirectory: cwd,
            controllingTTY: tty.map {
                AgentTTYCapture(
                    device: 42,
                    canonicalPath: $0,
                    source: .process,
                    capturedAt: now,
                    sourceIdentity: AgentProcessIdentity(
                        pid: pid,
                        startSeconds: seconds,
                        startMicroseconds: micros
                    )
                )
            },
            discoveredAt: now
        )
    }

    func testNativeClaudeProcessDetected() {
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/usr/local/bin/claude",
                arguments: ["claude", "--resume"]
            ),
            .nativeClaude
        )
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/opt/@anthropic-ai/claude-code/bin/claude.exe",
                arguments: ["/usr/local/bin/claude", "code"]
            ),
            .nativeClaude,
            "current Claude Code packages use a Mach-O claude.exe behind the claude symlink"
        )
    }

    func testNodeClaudeUsesKnownScriptPosition() {
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/usr/local/bin/node",
                arguments: [
                    "node",
                    "--no-warnings",
                    "/opt/lib/node_modules/@anthropic-ai/claude-code/cli.js",
                    "--resume",
                ]
            ),
            .nodeClaude
        )
    }

    func testNativeCodexProcessDetected() {
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/opt/homebrew/bin/codex",
                arguments: ["codex", "resume"]
            ),
            .nativeCodex
        )
    }

    func testApprovedLauncherWrappersUseOnlyTheCommandPosition() {
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/usr/bin/env",
                arguments: ["env", "NOTCHDECK_TEST=1", "codex", "resume"]
            ),
            .wrappedCodex
        )
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/opt/homebrew/bin/mise",
                arguments: ["mise", "exec", "--", "claude", "--resume"]
            ),
            .wrappedClaude
        )
        XCTAssertEqual(
            AgentProviderClassifier.classify(
                executablePath: "/opt/homebrew/bin/volta",
                arguments: ["volta", "run", "--", "codex", "exec", "check"]
            ),
            .wrappedCodex
        )
    }

    func testWrapperProviderWordsOutsideCommandPositionAreRejected() {
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/usr/bin/env",
            arguments: ["env", "NOTE=codex", "python3", "tool.py"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/bin/zsh",
            arguments: ["zsh", "-c", "codex"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/opt/homebrew/bin/mise",
            arguments: ["mise", "exec", "--", "python3", "prompt mentions claude"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/usr/bin/env",
            arguments: ["env", "codex", "app-server"]
        ))
        XCTAssertTrue(AgentProviderClassifier.shouldInspectArguments(executableBasename: "env"))
        XCTAssertFalse(AgentProviderClassifier.shouldInspectArguments(executableBasename: "python3"))
    }

    func testProcArgsParserStopsBeforeEnvironment() {
        var bytes = withUnsafeBytes(of: Int32(3).littleEndian) { Array($0) }
        bytes += Array("/usr/bin/node\0".utf8)
        bytes += [0]
        bytes += Array("node\0/path/@anthropic-ai/claude-code/cli.js\0--resume\0".utf8)
        bytes += Array("SECRET_TOKEN=must-not-be-argv\0".utf8)
        XCTAssertEqual(
            MacAgentProcessDiscovery.parseArguments(bytes),
            ["node", "/path/@anthropic-ai/claude-code/cli.js", "--resume"]
        )
    }

    func testUnrelatedProcessesAndArbitraryArgumentsAreRejected() {
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
            arguments: ["Electron", "project-claude-code"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
            arguments: ["/Applications/Claude.app/Contents/MacOS/Claude"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/bin/zsh",
            arguments: ["zsh", "-c", "echo codex"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "/tmp/cli.js", "claude"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/tmp/notchdeck-agent-hook",
            arguments: ["notchdeck-agent-hook", "--provider", "codex"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: "/tmp/codex",
            arguments: ["unrelated", "--label", "codex"]
        ))
    }

    func testCodexAdministrativeDaemonsAreNotAgentSessions() {
        let path = "/opt/codex"
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: path,
            arguments: ["codex", "-c", "features.code_mode_host=true", "app-server"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: path,
            arguments: ["codex", "remote-control", "start", "--json"]
        ))
        XCTAssertNil(AgentProviderClassifier.classify(
            executablePath: path,
            arguments: ["codex", "mcp-server"]
        ))
        XCTAssertEqual(AgentProviderClassifier.classify(
            executablePath: path,
            arguments: ["codex", "exec", "check this project"]
        ), .nativeCodex)
        XCTAssertEqual(AgentProviderClassifier.classify(
            executablePath: path,
            arguments: ["codex", "resume", "--last"]
        ), .nativeCodex)
    }

    func testPIDAndExactStartTimeFormIdentity() {
        let a = AgentProcessIdentity(pid: 7, startSeconds: 10, startMicroseconds: 1)
        let same = AgentProcessIdentity(pid: 7, startSeconds: 10, startMicroseconds: 1)
        let reused = AgentProcessIdentity(pid: 7, startSeconds: 11, startMicroseconds: 1)
        XCTAssertEqual(a, same)
        XCTAssertNotEqual(a, reused)
    }

    @MainActor
    func testProcessExistsWithoutHooksAndWithoutTTY() {
        let result = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(tty: nil)],
            now: now,
            makeID: { _ in UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isBridgeConnected)
        XCTAssertNil(result[0].terminalTTY)
        XCTAssertEqual(result[0].processPresence, .running)
        XCTAssertEqual(
            AgentSessionFilter.bucket(result[0]),
            .active,
            "missing hooks and TTY must not hide a live process"
        )
    }

    @MainActor
    func testCodexExistsWithoutTrustedHooks() {
        let result = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(provider: .codex, tty: nil)],
            now: now,
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(result.single?.provider, .codex)
        XCTAssertEqual(result.single?.processPresence, .running)
    }

    @MainActor
    func testLaterNilTTYDoesNotOverwriteValidCapture() {
        let first = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(tty: "ttys003")],
            now: now,
            makeID: { _ in UUID() }
        )
        let second = AgentProcessReconciler.reconcile(
            existing: first,
            snapshots: [snapshot(tty: nil)],
            now: now.addingTimeInterval(5),
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(second.single?.terminalTTY, "/dev/ttys003")
        XCTAssertEqual(second.single?.ttyCapture?.source, .process)
    }

    @MainActor
    func testRepeatedScanDoesNotDuplicateSession() {
        let id = UUID()
        let first = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot()],
            now: now,
            makeID: { _ in id }
        )
        let second = AgentProcessReconciler.reconcile(
            existing: first,
            snapshots: [snapshot()],
            now: now.addingTimeInterval(5),
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.single?.id, id)
    }

    @MainActor
    func testManagedSessionMergesWithUniqueMatchingProcess() {
        let managedID = UUID()
        var managed = AgentSession(
            id: managedID,
            provider: .codex,
            providerSessionID: "managed-provider-session",
            title: "Managed",
            projectPath: "/tmp/project",
            status: .starting,
            lastActivityAt: now,
            isManaged: true,
            startedAt: now
        )
        managed.processIdentity = nil
        let live = snapshot(
            pid: 200,
            seconds: UInt64(now.timeIntervalSince1970),
            provider: .codex
        )

        let result = AgentProcessReconciler.reconcile(
            existing: [managed],
            snapshots: [live],
            now: now,
            makeID: { _ in UUID() }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.single?.id, managedID)
        XCTAssertEqual(result.single?.providerSessionID, "managed-provider-session")
        XCTAssertTrue(result.single?.isManaged == true)
        XCTAssertEqual(result.single?.processIdentity, live.identity)
    }

    @MainActor
    func testConcurrentManagedSessionsInSameDirectoryUseExactLivePIDs() {
        let firstManagedID = UUID()
        let secondManagedID = UUID()
        let firstManaged = AgentSession(
            id: firstManagedID,
            provider: .codex,
            title: "Managed 1",
            projectPath: "/tmp/project",
            status: .starting,
            lastActivityAt: now,
            isManaged: true,
            startedAt: now
        )
        let secondManaged = AgentSession(
            id: secondManagedID,
            provider: .codex,
            title: "Managed 2",
            projectPath: "/tmp/project",
            status: .starting,
            lastActivityAt: now,
            isManaged: true,
            startedAt: now
        )
        let start = UInt64(now.timeIntervalSince1970)

        let result = AgentProcessReconciler.reconcile(
            existing: [firstManaged, secondManaged],
            snapshots: [
                snapshot(pid: 200, seconds: start, provider: .codex),
                snapshot(pid: 201, seconds: start, provider: .codex),
            ],
            now: now,
            managedProcessIDs: [
                firstManagedID: 200,
                secondManagedID: 201,
            ],
            makeID: { _ in UUID() }
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(
            result.first(where: { $0.id == firstManagedID })?.processIdentity?.pid,
            200
        )
        XCTAssertEqual(
            result.first(where: { $0.id == secondManagedID })?.processIdentity?.pid,
            201
        )
        XCTAssertEqual(result.compactMap(\.processIdentity).count, 2)
    }

    @MainActor
    func testManagedPIDMappingCannotBeHijackedByEarlierDirectoryMatch() {
        let managedID = UUID()
        let managed = AgentSession(
            id: managedID,
            provider: .codex,
            title: "Managed",
            projectPath: "/tmp/project",
            status: .starting,
            lastActivityAt: now,
            isManaged: true,
            startedAt: now
        )
        let start = UInt64(now.timeIntervalSince1970)

        let result = AgentProcessReconciler.reconcile(
            existing: [managed],
            snapshots: [
                snapshot(pid: 199, seconds: start, provider: .codex),
                snapshot(pid: 200, seconds: start, provider: .codex),
            ],
            now: now,
            managedProcessIDs: [managedID: 200],
            makeID: { _ in UUID() }
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(
            result.first(where: { $0.id == managedID })?.processIdentity?.pid,
            200
        )
        XCTAssertNotNil(result.first(where: { $0.processIdentity?.pid == 199 }))
    }

    @MainActor
    func testReusedPIDEndsOldSessionAndCreatesNewSession() {
        let old = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(seconds: 10)],
            now: now,
            makeID: { _ in UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )
        let next = AgentProcessReconciler.reconcile(
            existing: old,
            snapshots: [snapshot(seconds: 11)],
            now: now.addingTimeInterval(5),
            makeID: { identity in
                identity.startSeconds == 11
                    ? UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
                    : UUID()
            }
        )
        XCTAssertEqual(next.count, 2)
        XCTAssertEqual(next.first(where: { $0.processIdentity?.startSeconds == 10 })?.processPresence, .ended)
        XCTAssertEqual(next.first(where: { $0.processIdentity?.startSeconds == 11 })?.processPresence, .running)
    }

    @MainActor
    func testEndedProcessTransitionsToRecent() {
        let running = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot()],
            now: now,
            makeID: { _ in UUID() }
        )
        let oneMiss = AgentProcessReconciler.reconcile(
            existing: running,
            snapshots: [],
            now: now.addingTimeInterval(5),
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(oneMiss.single?.processPresence, .running)
        let ended = AgentProcessReconciler.reconcile(
            existing: oneMiss,
            snapshots: [],
            now: now.addingTimeInterval(10),
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(ended.single?.processPresence, .ended)
        XCTAssertEqual(AgentSessionFilter.bucket(ended[0]), .recent)
    }

    @MainActor
    func testSameDirectoryConcurrentSessionsRemainDistinct() {
        let result = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(pid: 100), snapshot(pid: 101)],
            now: now,
            makeID: { _ in UUID() }
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.compactMap(\.processIdentity)).count, 2)
    }

    @MainActor
    func testHookSessionArrivingBeforeFirstScanMergesWhenProcessMatchIsUnambiguous() {
        let hookID = UUID()
        var hookSession = AgentSession(
            id: hookID,
            provider: .claudeCode,
            providerSessionID: "provider-session",
            title: "project",
            projectPath: "/tmp/project",
            status: .running,
            lastActivityAt: now,
            isManaged: false
        )
        hookSession.isBridgeConnected = true

        let result = AgentProcessReconciler.reconcile(
            existing: [hookSession],
            snapshots: [snapshot(pid: 100)],
            now: now,
            makeID: { _ in UUID() }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.single?.id, hookID)
        XCTAssertEqual(result.single?.providerSessionID, "provider-session")
        XCTAssertEqual(result.single?.processIdentity?.pid, 100)
    }

    @MainActor
    func testHookSessionDoesNotMergeByDirectoryWhenTwoLiveProcessesMatch() {
        let hookID = UUID()
        var hookSession = AgentSession(
            id: hookID,
            provider: .claudeCode,
            title: "project",
            projectPath: "/tmp/project",
            status: .running,
            lastActivityAt: now,
            isManaged: false
        )
        hookSession.isBridgeConnected = true

        let result = AgentProcessReconciler.reconcile(
            existing: [hookSession],
            snapshots: [snapshot(pid: 100), snapshot(pid: 101)],
            now: now,
            makeID: { identity in
                UUID(uuidString: identity.pid == 100
                    ? "00000000-0000-0000-0000-000000000001"
                    : "00000000-0000-0000-0000-000000000002")!
            }
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertNil(result.first(where: { $0.id == hookID })?.processIdentity)
        XCTAssertEqual(result.compactMap(\.processIdentity).count, 2)
    }

    @MainActor
    func testExternalWindowDoesNotDuplicateAuthoritativeProcessSession() {
        let store = AgentSessionStore(fileName: "process-external-\(UUID().uuidString).json")
        store.replaceDiscoveredProcesses([snapshot(pid: 100)], now: now)

        var external = AgentSession(
            provider: .external,
            title: "claude — project",
            projectPath: "",
            status: .running,
            isManaged: false
        )
        external.externalWindowTitle = "claude — project"
        store.replaceExternal([external])

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.single?.processIdentity?.pid, 100)
    }

    @MainActor
    func testHookEnrichmentUsesExactAncestorIdentity() {
        let processSessions = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(pid: 100), snapshot(pid: 101)],
            now: now,
            makeID: { _ in UUID() }
        )
        let match = AgentHookProcessCorrelator.match(
            provider: .claudeCode,
            ancestorIdentities: [
                AgentProcessIdentity(pid: 500, startSeconds: 1, startMicroseconds: 0),
                AgentProcessIdentity(pid: 101, startSeconds: 10, startMicroseconds: 20),
            ],
            cwd: "/tmp/project",
            discoveredAt: now,
            sessions: processSessions
        )
        XCTAssertEqual(match?.sessionID, processSessions.first(where: { $0.pid == 101 })?.id)
        XCTAssertEqual(match?.confidence, .exactAncestry)
    }

    @MainActor
    func testExactAncestryStillCorrelatesDuringDebouncedEndedState() {
        let processSessions = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(pid: 100)],
            now: now,
            makeID: { _ in UUID() }
        )
        var ended = processSessions[0]
        ended.processPresence = .ended
        guard let identity = ended.processIdentity else {
            return XCTFail("process identity missing")
        }

        let match = AgentHookProcessCorrelator.match(
            provider: .claudeCode,
            ancestorIdentities: [identity],
            cwd: "/tmp/project",
            discoveredAt: now.addingTimeInterval(1),
            sessions: [ended]
        )

        XCTAssertEqual(match?.sessionID, ended.id)
        XCTAssertEqual(match?.confidence, .exactAncestry)
    }

    @MainActor
    func testAmbiguousSameDirectoryFallbackDoesNotMerge() {
        let sessions = AgentProcessReconciler.reconcile(
            existing: [],
            snapshots: [snapshot(pid: 100), snapshot(pid: 101)],
            now: now,
            makeID: { _ in UUID() }
        )
        XCTAssertNil(AgentHookProcessCorrelator.match(
            provider: .claudeCode,
            ancestorIdentities: [],
            cwd: "/tmp/project",
            discoveredAt: now.addingTimeInterval(1),
            sessions: sessions
        ))
    }

    func testBoundedAncestryStopsAtLimitAndLoops() {
        let records: [Int32: AgentProcessRecord] = [
            50: .init(identity: .init(pid: 50, startSeconds: 1, startMicroseconds: 0), parentPID: 51),
            51: .init(identity: .init(pid: 51, startSeconds: 1, startMicroseconds: 0), parentPID: 50),
        ]
        let chain = ProcessAncestryResolver.resolve(
            from: 50,
            maxDepth: 16,
            record: { records[$0] }
        )
        XCTAssertEqual(chain.map(\.pid), [50, 51])
    }

    func testNativeDescendantSuppressesWrapperShadowSession() {
        let wrapper = snapshot(
            pid: 300,
            parentPID: 1,
            provider: .codex,
            classification: .wrappedCodex
        )
        let native = snapshot(
            pid: 301,
            parentPID: 300,
            provider: .codex,
            classification: .nativeCodex
        )
        let records: [Int32: AgentProcessRecord] = [
            300: .init(identity: wrapper.identity, parentPID: 1),
        ]

        let result = AgentProcessSnapshotNormalizer.preferProviderProcesses(
            [wrapper, native],
            record: { records[$0] }
        )

        XCTAssertEqual(result.map(\.identity), [native.identity])
        XCTAssertEqual(
            AgentProcessSnapshotNormalizer.preferProviderProcesses(
                [wrapper],
                record: { records[$0] }
            ).map(\.identity),
            [wrapper.identity],
            "a wrapper-only provider remains discoverable"
        )
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

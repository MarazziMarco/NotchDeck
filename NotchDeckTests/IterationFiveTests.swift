import XCTest
import Darwin
@testable import NotchDeck

final class CompactPomodoroPriorityTests: XCTestCase {
    func testPomodoroOutranksClipboard() {
        var input = CompactStatusInputs()
        input.pomodoroRunningRemaining = "24:37"
        input.clipboardSymbol = "doc.on.clipboard"
        // Pomodoro must win over Clipboard for the single compact slot.
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .pomodoroRunning(remaining: "24:37"))
    }

    func testClipboardShownOnlyWhenNothingHigher() {
        var input = CompactStatusInputs()
        input.clipboardSymbol = "doc.on.clipboard"
        XCTAssertEqual(CompactStatusCoordinator.resolve(input), .clipboard(symbol: "doc.on.clipboard"))
    }
}

@MainActor
final class NotchWingGeometryTests: XCTestCase {
    func testWingsDoNotIntersectHousing() {
        let info = NotchLayoutInfo()
        info.hasNotch = true
        info.compactPanelWidth = 320
        info.housingWidth = 200
        let wing = info.wingWidth
        XCTAssertEqual(wing, 60, accuracy: 0.5)   // (320-200)/2

        // Leading wing [0, wing], housing [wing, panel-wing], trailing [panel-wing, panel].
        let leading = 0.0...Double(wing)
        let housing = Double(wing)...Double(info.compactPanelWidth - wing)
        let trailing = Double(info.compactPanelWidth - wing)...Double(info.compactPanelWidth)
        // Wings sit strictly outside the housing interior.
        XCTAssertLessThanOrEqual(leading.upperBound, housing.lowerBound)
        XCTAssertGreaterThanOrEqual(trailing.lowerBound, housing.upperBound)
    }

    func testNonNotchedUsesFullWidthPill() {
        let info = NotchLayoutInfo()
        info.hasNotch = false
        info.compactPanelWidth = 200
        XCTAssertEqual(info.wingWidth, 200)   // centered pill, full width
    }
}

final class HookCommandQuotingTests: XCTestCase {
    func testCommandQuotesSpacedAbsolutePath() {
        let helper = "/Users/tester/Library/Application Support/NotchDeck/notchdeck-agent-hook"
        let cmd = HookInstaller.command(helper: helper, provider: .claudeCode, event: .sessionStarted)
        // Double-quoted absolute path (survives `sh -c`), CLI provider name, event.
        XCTAssertTrue(cmd.hasPrefix("\"\(helper)\""))
        XCTAssertFalse(cmd.hasPrefix("~"))
        XCTAssertTrue(cmd.contains("--provider claude"))
        XCTAssertTrue(cmd.contains("--event sessionStarted"))
    }

    func testCodexUsesCodexProviderName() {
        let cmd = HookInstaller.command(helper: "/x/notchdeck-agent-hook", provider: .codex, event: .permissionRequested)
        XCTAssertTrue(cmd.contains("--provider codex"))
    }

    func testProviderParsingAliases() {
        XCTAssertEqual(TerminalAgentProvider.parse("claude"), .claudeCode)
        XCTAssertEqual(TerminalAgentProvider.parse("claudeCode"), .claudeCode)
        XCTAssertEqual(TerminalAgentProvider.parse("codex"), .codex)
        XCTAssertEqual(TerminalAgentProvider.claudeCode.cliName, "claude")
        XCTAssertEqual(TerminalAgentProvider.codex.cliName, "codex")
    }
}

/// Deterministic media boundary for tests — never launches osascript / Music.app.
final class FakeNowPlayingProvider: NowPlayingProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var snapshotCount: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func snapshot() -> NowPlayingSnapshot {
        lock.lock(); _count += 1; lock.unlock(); return .empty
    }
    func playPause(currentApp: String?) {}
    func next(currentApp: String?) {}
    func previous(currentApp: String?) {}
}

@MainActor
final class SharedStoreTests: XCTestCase {
    func testCoordinatorAndEnvironmentShareOneStore() {
        // Uses the fake media boundary → no Music.app / osascript / Automation prompt.
        let env = AppEnvironment(settings: SettingsStore.inMemory(), mediaProvider: FakeNowPlayingProvider())
        XCTAssertTrue(env.agentStore === env.agents.store)   // same instance the bridge updates
    }

    func testTestEnvironmentUsesFakeMediaNoExternalProcess() {
        let fake = FakeNowPlayingProvider()
        let env = AppEnvironment(settings: SettingsStore.inMemory(), mediaProvider: fake)
        // Constructed + configured (which starts Now Playing) with no external
        // process launch; the fake yields an empty, deterministic state.
        XCTAssertNil(env.nowPlaying.track)
        XCTAssertFalse(env.nowPlaying.providerAvailable)
        // Prove the fake boundary was actually used (not the AppleScript provider).
        let exp = expectation(description: "fake polled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if fake.snapshotCount >= 1 { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2)
    }

    func testImmediatePublishedUpdateOnUpsert() {
        let store = AgentSessionStore(fileName: "pub-\(UUID().uuidString).json")
        let exp = expectation(description: "published change")
        let c = store.$sessions.dropFirst().sink { _ in exp.fulfill() }
        store.upsert(AgentSession(provider: .codex, title: "x", projectPath: "/tmp"))
        wait(for: [exp], timeout: 1)
        c.cancel()
    }
}

/// Real Unix-socket round trip: an in-process client connects to the live bridge
/// socket and the store must receive the session. Exercises the actual socket
/// path, not a fake.
@MainActor
final class BridgeSocketRoundTripTests: XCTestCase {
    func testBridgeReceivesEventOverRealSocket() async throws {
        let store = AgentSessionStore(fileName: "rt-\(UUID().uuidString).json")
        let stats = TerminalBridgeStats()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-roundtrip-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = TerminalAgentBridge(
            store: store,
            stats: stats,
            socketURL: directory.appendingPathComponent("bridge.sock")
        )
        await bridge.start()
        defer { Task { await bridge.stop() } }
        try await Task.sleep(nanoseconds: 250_000_000)

        let path = await bridge.socketPath
        let fd = Self.connectClient(path)
        XCTAssertGreaterThanOrEqual(fd, 0, "client socket connect failed")

        let sid = "rt-\(UUID().uuidString.prefix(6))"
        let event = TerminalAgentEvent(type: .sessionStarted, provider: .claudeCode,
                                       sessionID: sid, cwd: "/tmp/proj", timestamp: 1)
        let line = TerminalAgentCodec.encodeLine(event)!
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }

        // Poll the store for the connected session.
        var found = false
        for _ in 0..<40 {
            if store.sessions.contains(where: { $0.providerSessionID == sid && $0.isBridgeConnected }) {
                found = true; break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        close(fd)
        XCTAssertTrue(found, "bridge did not insert session from real socket event")
        XCTAssertGreaterThan(stats.decodedEvents, 0)
    }

    private static func connectClient(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { c in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), c, capacity - 1)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        if ok != 0 { close(fd); return -1 }
        return fd
    }
}

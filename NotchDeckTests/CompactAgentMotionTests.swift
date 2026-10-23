import XCTest
@testable import NotchDeck

final class CompactAgentMotionTests: XCTestCase {
    private func session(_ provider: AgentProviderKind, _ status: AgentSessionStatus) -> AgentSession {
        AgentSession(provider: provider, title: "s", projectPath: "/p", status: status)
    }

    func testOnlyARunningSessionMarksItsProviderAsWorking() {
        let presence = CompactAgentProviderPresence(activeSessions: [
            session(.claudeCode, .running),
            session(.codex, .idle),
        ])
        XCTAssertTrue(presence.isWorking(.claudeCode))
        XCTAssertFalse(presence.isWorking(.codex))
        XCTAssertTrue(presence.showsCodex, "an idle provider is still shown")
    }

    func testAnyRunningSessionOfAProviderCounts() {
        let presence = CompactAgentProviderPresence(activeSessions: [
            session(.codex, .idle),
            session(.codex, .running),
        ])
        XCTAssertTrue(presence.isWorking(.codex))
        XCTAssertFalse(presence.isWorking(.claudeCode))
    }

    func testWorkingFlagReachesEachProviderSlot() throws {
        let presentation = CompactAgentPresentation(
            state: .activeSessions(count: 2),
            providers: CompactAgentProviderPresence(
                showsClaude: true, showsCodex: true, claudeWorking: false, codexWorking: true)
        )
        let activity = try XCTUnwrap(CompactAgentActivityFactory.make(for: presentation))
        XCTAssertEqual(activity.splitLeading?.providerWorking, false)
        XCTAssertEqual(activity.splitTrailing?.providerWorking, true)
    }

    func testMotionFollowsWorkAttentionAndReduceMotion() {
        XCTAssertEqual(CompactAgentMotion.resolve(model: .activeSessions(count: 1), working: true, reduceMotion: false), .work)
        XCTAssertEqual(CompactAgentMotion.resolve(model: .activeSessions(count: 1), working: false, reduceMotion: false), .still,
                       "an open but idle agent stays still")
        XCTAssertEqual(CompactAgentMotion.resolve(model: .approvalRequired(count: 1), working: false, reduceMotion: false), .breathe)
        XCTAssertEqual(CompactAgentMotion.resolve(model: .approvalRequired(count: 1), working: true, reduceMotion: false), .breathe,
                       "attention states keep their own cue")
        XCTAssertEqual(CompactAgentMotion.resolve(model: .activeSessions(count: 1), working: true, reduceMotion: true), .still)
        XCTAssertEqual(CompactAgentMotion.resolve(model: .hidden, working: true, reduceMotion: false), .still)
    }

    func testCodexLogoIsSlightlyLargerAndStaysInsideItsWing() {
        XCTAssertEqual(CompactAgentIndicatorGeometry.logoScale(for: .claudeCode), 1)
        XCTAssertGreaterThan(CompactAgentIndicatorGeometry.logoScale(for: .codex), 1)
        // Largest drawn size (Codex at the top of the working pulse) must still
        // fit the wing's notch-safe clearance.
        let peak = CompactAgentIndicatorGeometry.iconSize
            * CompactAgentIndicatorGeometry.logoScale(for: .codex)
            * CompactAgentMotion.workScaleRange.upperBound
        let growthPerSide = (peak - CompactAgentIndicatorGeometry.iconSize) / 2
        XCTAssertLessThan(growthPerSide, CompactAgentIndicatorGeometry.notchSafeInset / 2)
    }
}

import XCTest
@testable import NotchDeck

final class AgentOverviewUITests: XCTestCase {
    private func session(provider: AgentProviderKind = .claudeCode,
                         tty: String? = "/dev/ttys001",
                         approval: Bool = false) -> AgentSession {
        var value = AgentSession(
            provider: provider,
            title: "project",
            projectPath: "/tmp/project",
            status: approval ? .waitingForApproval : .running,
            isManaged: false,
            isBridgeConnected: approval,
            terminalTTY: tty
        )
        if approval {
            value.approval = PendingApproval(
                provider: provider,
                sessionID: "s",
                requestID: "r",
                toolUseID: nil,
                turnID: "t",
                rawEventName: "PermissionRequest",
                toolName: "Bash",
                summary: "Permission requested",
                receivedAt: Date(),
                expiresAt: Date().addingTimeInterval(30),
                state: .pending,
                handlingMode: .notchWithTerminalFallback,
                fallbackDeadline: Date().addingTimeInterval(8),
                nativePromptExpected: true
            )
        }
        return value
    }

    func testCardPresentationDoesNotDuplicatePermissionStatus() {
        let presentation = AgentCardPresentation(
            session: session(approval: true),
            bucket: .active
        )
        XCTAssertEqual(presentation.lifecycleLabel, "Active")
        XCTAssertEqual(presentation.statusLine, "Claude Code · Permission requested")
        XCTAssertNil(presentation.preview)
        XCTAssertEqual(
            presentation.statusLine.components(separatedBy: "Permission requested").count - 1,
            1
        )
    }

    func testCodexLabelsNeverSayClaude() {
        var value = session(provider: .codex, approval: true)
        value.approval?.state = .sent
        let presentation = AgentCardPresentation(session: value, bucket: .active)
        XCTAssertEqual(presentation.deliveryLabel, "Sent to Codex")
        XCTAssertFalse(presentation.deliveryLabel?.contains("Claude") ?? true)
    }

    func testMissingTTYIsVisibleAndFocusLabelIsContextual() {
        let presentation = AgentCardPresentation(
            session: session(tty: nil),
            bucket: .active
        )
        XCTAssertEqual(presentation.terminalNotice, "Terminal identifier unavailable")
        XCTAssertEqual(presentation.focusAccessibilityLabel, "Focus Terminal for project")
    }

    func testRecentLifecycleIsExplicit() {
        XCTAssertEqual(
            AgentCardPresentation(session: session(), bucket: .recent).lifecycleLabel,
            "Recent"
        )
    }

    func testAgentDetailRouteIsAbsentFromProductionSources() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDirectory.deletingLastPathComponent()
        let agentsFace = try String(contentsOf:
            root.appendingPathComponent("NotchDeck/Agents/AgentsFaceView.swift"))
        let focusMode = try String(contentsOf:
            root.appendingPathComponent("NotchDeck/Notch/FocusMode.swift"))
        let expanded = try String(contentsOf:
            root.appendingPathComponent("NotchDeck/Notch/ExpandedNotchView.swift"))
        let appState = try String(contentsOf:
            root.appendingPathComponent("NotchDeck/App/AppState.swift"))

        XCTAssertFalse(agentsFace.contains(".onTapGesture"))
        XCTAssertFalse(agentsFace.contains("focusAgent("))
        XCTAssertFalse(focusMode.contains("AgentFocusContainer"))
        XCTAssertFalse(expanded.contains("focusedAgentID"))
        XCTAssertFalse(appState.contains("focusedAgentID"))
        XCTAssertFalse(appState.contains("focusAgent("))
    }
}

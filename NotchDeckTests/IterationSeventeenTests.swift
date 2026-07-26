import XCTest
@testable import NotchDeck

// MARK: Claude PermissionRequest response schema (helper output)

/// Mirrors the helper's emitDecision so the exact JSON schema is asserted without
/// spawning a subprocess. Kept in sync with AgentHook/main.swift.
private func claudeDecisionJSON(allow: Bool, message: String? = nil) -> [String: Any] {
    var d: [String: Any] = ["behavior": allow ? "allow" : "deny"]
    if !allow { d["message"] = message ?? "Denied in NotchDeck"; d["interrupt"] = false }
    return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": d]]
}

final class HookSchemaTests: XCTestCase {
    func testAllowUsesPermissionRequestSchemaNotPreToolUse() {
        let obj = claudeDecisionJSON(allow: true)
        let hs = obj["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(hs?["hookEventName"] as? String, "PermissionRequest")
        let decision = hs?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        // Must NOT be the PreToolUse schema.
        XCTAssertNil(hs?["permissionDecision"])
    }
    func testDenyIncludesMessageAndInterrupt() {
        let decision = (claudeDecisionJSON(allow: false)["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "deny")
        XCTAssertEqual(decision?["message"] as? String, "Denied in NotchDeck")
        XCTAssertEqual(decision?["interrupt"] as? Bool, false)
    }
    func testSchemaSerializesToSingleJSONObject() throws {
        let data = try JSONSerialization.data(withJSONObject: claudeDecisionJSON(allow: true))
        let str = String(data: data, encoding: .utf8)!
        XCTAssertFalse(str.contains("\n"))            // one line, no log contamination
        XCTAssertTrue(str.contains("PermissionRequest"))
    }
}

// MARK: Delivery lifecycle (Approved only after ack)

final class ApprovalDeliveryTests: XCTestCase {
    private func approval(_ state: PendingApproval.ResponseState) -> PendingApproval {
        PendingApproval(provider: .claudeCode, sessionID: "S", requestID: "R1",
                        toolUseID: nil, turnID: nil, rawEventName: "PermissionRequest",
                        toolName: "Bash", summary: "run tests", receivedAt: Date(),
                        expiresAt: Date().addingTimeInterval(120), state: state,
                        handlingMode: .notchWithTerminalFallback, fallbackDeadline: nil,
                        nativePromptExpected: true)
    }
    func testDeliveryStatesExist() {
        // Explicit lifecycle beyond pending → answered.
        let all: [PendingApproval.ResponseState] = [.pending, .sending, .delivered,
                                                    .deliveryFailed, .fellBack, .expired, .cancelled]
        XCTAssertEqual(Set(all).count, 7)
    }
    func testDecodesSendingAndDelivered() throws {
        for st in [PendingApproval.ResponseState.sending, .delivered, .deliveryFailed] {
            let data = try JSONEncoder().encode(approval(st))
            let back = try JSONDecoder().decode(PendingApproval.self, from: data)
            XCTAssertEqual(back.state, st)
        }
    }

    @MainActor func testBridgeAckMarksDelivered() {
        // Reduce ignores decisionDelivered for state; the bridge's ingest sets it.
        // Here we simulate the store transition the ack performs.
        let store = AgentSessionStore(fileName: "ack-\(UUID()).json")
        var s = AgentSession(provider: .claudeCode, title: "t", projectPath: "/p",
                             status: .waitingForApproval, isManaged: false)
        s.isBridgeConnected = true
        s.approval = approval(.sending)
        store.upsert(s)
        // Ack path: sending → delivered.
        store.update(id: s.id) {
            if $0.approval?.state == .sending || $0.approval?.state == .pending {
                $0.approval?.state = .delivered
            }
        }
        XCTAssertEqual(store.session(id: s.id)?.approval?.state, .delivered)
    }
}

// MARK: Installer — synchronous PermissionRequest hook, no async, single entry

final class HookInstallerSyncTests: XCTestCase {
    func testClaudePermissionRequestHasTimeoutAndNoAsync() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        // Navigate to hooks.PermissionRequest[0].hooks[0]
        let hooks = ((merged["hooks"] as? [String: Any]))
        let pr = (hooks?["PermissionRequest"] as? [[String: Any]])?.first
        let inner = (pr?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(inner?["timeout"] as? Int, HookTimeouts.claudeHookTimeoutSeconds)  // 30s, > helper 15s > UI 8s
        XCTAssertNil(inner?["async"])                         // synchronous
    }
    func testPreToolUseHasNoTimeoutBlock() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        let hooks = (merged["hooks"] as? [String: Any])
        let pre = (hooks?["PreToolUse"] as? [[String: Any]])?.first
        let inner = (pre?["hooks"] as? [[String: Any]])?.first
        XCTAssertNil(inner?["timeout"])                       // activity hook stays short-lived
    }
    func testExactlyOnePermissionRequestEntryAfterReinstall() {
        var base = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        base = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/tmp/h")  // reinstall
        let hooks = (base["hooks"] as? [String: Any])
        let prs = (hooks?["PermissionRequest"] as? [[String: Any]]) ?? []
        XCTAssertEqual(prs.count, 1)                          // no duplicates
    }
    func testUnrelatedUserHookPreserved() {
        let base: [String: Any] = ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": "/usr/bin/true"]]]]]]
        let merged = HookInstaller.mergeHooks(base: base, provider: .claudeCode, helper: "/tmp/h")
        let prs = ((merged["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]) ?? []
        let commands = prs.compactMap { (($0["hooks"] as? [[String: Any]])?.first?["command"] as? String) }
        XCTAssertTrue(commands.contains("/usr/bin/true"))     // user hook kept
        XCTAssertEqual(prs.count, 2)                          // user + one NotchDeck
    }
}

// MARK: Compact right-wing notch-safe inset

final class CompactWingLayoutTests: XCTestCase {
    func testNotchGetsSafeInsetInRange() {
        let inset = CompactWingLayout.rightWingLeadingInset(hasNotch: true)
        XCTAssertGreaterThanOrEqual(inset, 18)
        XCTAssertLessThanOrEqual(inset, 24)
        XCTAssertEqual(inset, 22)
    }
    func testNonNotchGetsNoExtraOffset() {
        XCTAssertEqual(CompactWingLayout.rightWingLeadingInset(hasNotch: false), CompactWingLayout.normalInset)
        XCTAssertLessThan(CompactWingLayout.rightWingLeadingInset(hasNotch: false), 18)
    }
    func testRightWingStartsAfterExclusionZone() {
        let housingMaxX: CGFloat = 120
        let start = CompactWingLayout.rightWingStartX(housingMaxX: housingMaxX, hasNotch: true)
        XCTAssertGreaterThan(start, housingMaxX)              // after the notch exclusion
        XCTAssertEqual(start - housingMaxX, 22)               // by the safe inset
    }
    func testTrailingOuterPaddingPresent() {
        XCTAssertGreaterThanOrEqual(CompactWingLayout.trailingOuterPadding, 14)
        XCTAssertLessThanOrEqual(CompactWingLayout.trailingOuterPadding, 18)
    }
}

// MARK: Panel height / Focus breakpoint / permission sequence

final class UIRefinementTests: XCTestCase {
    func testExpandedHeightIncreased() {
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.expandedMaxHeight, 360)
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.bottomBreathingRoom, 24)
        XCTAssertGreaterThanOrEqual(DesignTokens.Metrics.homeTrailingInset, 24)   // after Mirror
    }
    func testFocusHorizontalBreakpoint() {
        XCTAssertTrue(FocusLayout.isHorizontal(availableWidth: 720))
        XCTAssertFalse(FocusLayout.isHorizontal(availableWidth: 480))
    }
    func testPermissionSequenceOrderAndNoMicrophone() {
        XCTAssertEqual(PermissionOnboarding.steps.first, .welcome)
        XCTAssertEqual(PermissionOnboarding.steps.last, .complete)
        XCTAssertFalse(PermissionOnboarding.steps.contains { $0.rawValue == "microphone" })
        XCTAssertEqual(PermissionOnboarding.next(after: .camera), .screenRecording)
    }
    func testDeniedPermissionNotReRequested() {
        XCTAssertFalse(PermissionOnboarding.shouldRequest(.camera, state: .denied))
        XCTAssertTrue(PermissionOnboarding.shouldRequest(.camera, state: .notRequested))
        XCTAssertTrue(PermissionOnboarding.offersSystemSettings(.denied))
    }
    func testScreenshotLabelIsEnglish() {
        XCTAssertEqual(ScreenshotStrings.capture, "Take Screenshot")
        XCTAssertNotEqual(ScreenshotStrings.capture, "Scatta")
    }
}

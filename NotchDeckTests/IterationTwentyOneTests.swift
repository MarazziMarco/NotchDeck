import XCTest
@testable import NotchDeck

// MARK: Permissions setup wiring

final class PermissionsSetupWiringTests: XCTestCase {
    func testSetupShownOnFirstLaunchByDefault() {
        // Default false → the setup window is presented on first launch.
        XCTAssertFalse(AppSettings().permissionsSetupCompleted)
    }
    func testSequenceHasNoMicrophone() {
        XCTAssertFalse(PermissionOnboarding.steps.contains { $0.rawValue == "microphone" })
    }
    func testSequenceOrder() {
        let requesting = PermissionOnboarding.steps.filter { $0.requestsPermission }
        XCTAssertEqual(requesting, [.camera, .screenRecording, .downloads, .terminalAutomation])
    }
    func testDownloadsBookmarkPersists() throws {
        var s = AppSettings()
        s.downloadsBookmark = Data([1, 2, 3])
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.downloadsBookmark, Data([1, 2, 3]))
    }
    func testDeniedNotReRequestedSequentially() {
        // A denied permission is not auto-prompted again.
        XCTAssertFalse(PermissionOnboarding.shouldRequest(.screenRecording, state: .denied))
        XCTAssertTrue(PermissionOnboarding.offersSystemSettings(.denied))
    }
}

// MARK: Hook mismatch detection

final class HookMismatchTests: XCTestCase {
    func testFreshInstallIsUpToDate() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        XCTAssertTrue(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }
    func testStaleTimeoutDetected() {
        // Simulate an old install whose PermissionRequest timeout is 20, not 30.
        var merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        var hooks = merged["hooks"] as! [String: Any]
        var prs = hooks["PermissionRequest"] as! [[String: Any]]
        var entry = prs[0]
        var inner = (entry["hooks"] as! [[String: Any]])
        inner[0]["timeout"] = 20
        entry["hooks"] = inner
        prs[0] = entry
        hooks["PermissionRequest"] = prs
        merged["hooks"] = hooks
        XCTAssertFalse(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }
    func testAsyncPermissionRequestDetectedStale() {
        var merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        var hooks = merged["hooks"] as! [String: Any]
        var prs = hooks["PermissionRequest"] as! [[String: Any]]
        var entry = prs[0]
        var inner = (entry["hooks"] as! [[String: Any]])
        inner[0]["async"] = true
        entry["hooks"] = inner
        prs[0] = entry
        hooks["PermissionRequest"] = prs
        merged["hooks"] = hooks
        XCTAssertFalse(HookInstaller.configIsUpToDate(merged, provider: .claudeCode))
    }
    func testNoHooksIsNotUpToDate() {
        XCTAssertFalse(HookInstaller.configIsUpToDate([:], provider: .claudeCode))
    }
}

import XCTest
@testable import NotchDeck

/// Exercises `LaunchPadPresenceBridge`'s state handling using injectable
/// `NotificationCenter`s for both the distributed presence bus and the
/// workspace termination hook — deterministic, in-process delivery instead
/// of the real buses. Deliberately `@testable import NotchDeck` only (no
/// `import ActionKit`): the bridge re-exports the two notification names it
/// needs via `LaunchPadPresenceBridge.didShow`/`.didHide`, so NotchDeckTests
/// doesn't need to link ActionKit directly (see project.yml — this test
/// bundle is hosted inside NotchDeck.app, and linking the same SPM package
/// product into both risks duplicate-class warnings).
@MainActor
final class LaunchPadPresenceBridgeTests: XCTestCase {
    func testShowSuspendsAndHideResumes() {
        let center = NotificationCenter()
        var seen: [Bool] = []
        let suspendedExp = expectation(description: "suspended")
        let resumedExp = expectation(description: "resumed")
        let bridge = LaunchPadPresenceBridge(center: center, workspaceCenter: NotificationCenter()) { suspended in
            seen.append(suspended)
            if suspended { suspendedExp.fulfill() } else { resumedExp.fulfill() }
        }

        center.post(name: LaunchPadPresenceBridge.didShow, object: nil)
        wait(for: [suspendedExp], timeout: 2.0)
        XCTAssertTrue(bridge.isSuspended)

        center.post(name: LaunchPadPresenceBridge.didHide, object: nil)
        wait(for: [resumedExp], timeout: 2.0)
        XCTAssertFalse(bridge.isSuspended)

        XCTAssertEqual(seen, [true, false])
        bridge.invalidate()
    }

    func testDuplicateShowIsIdempotent() {
        let center = NotificationCenter()
        var changeCount = 0
        let firstChange = expectation(description: "first change")
        let unwantedSecondChange = expectation(description: "unwanted second change")
        unwantedSecondChange.isInverted = true
        let bridge = LaunchPadPresenceBridge(center: center, workspaceCenter: NotificationCenter()) { _ in
            changeCount += 1
            if changeCount == 1 { firstChange.fulfill() } else { unwantedSecondChange.fulfill() }
        }

        center.post(name: LaunchPadPresenceBridge.didShow, object: nil)
        wait(for: [firstChange], timeout: 2.0)
        center.post(name: LaunchPadPresenceBridge.didShow, object: nil) // redundant: no 2nd callback expected

        wait(for: [unwantedSecondChange], timeout: 0.3)
        XCTAssertEqual(changeCount, 1)
        XCTAssertTrue(bridge.isSuspended)
        bridge.invalidate()
    }

    /// Drives the real `NSWorkspace.didTerminateApplicationNotification`
    /// path end to end, through an injected workspace `NotificationCenter`
    /// rather than the real one. `NSRunningApplication` has no public
    /// initializer, so there's no way to fabricate a termination notice for
    /// an arbitrary bundle id — instead the bridge's `bundleId` is injected
    /// to match the one real `NSRunningApplication` a test can get a handle
    /// on: the test process itself, `NSRunningApplication.current`.
    func testWorkspaceTerminationOfMatchingBundleIdResumes() throws {
        guard let testBundleId = NSRunningApplication.current.bundleIdentifier else {
            throw XCTSkip("test process has no bundle id to match against")
        }
        let center = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        var seen: [Bool] = []
        let suspendedExp = expectation(description: "suspended")
        let resumedExp = expectation(description: "resumed via termination")
        let bridge = LaunchPadPresenceBridge(
            center: center, workspaceCenter: workspaceCenter, bundleId: testBundleId
        ) { suspended in
            seen.append(suspended)
            if suspended { suspendedExp.fulfill() } else { resumedExp.fulfill() }
        }

        center.post(name: LaunchPadPresenceBridge.didShow, object: nil)
        wait(for: [suspendedExp], timeout: 2.0)

        workspaceCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        wait(for: [resumedExp], timeout: 2.0)

        XCTAssertEqual(seen, [true, false])
        bridge.invalidate()
    }

    /// Same termination notice, but the bridge is watching for a different
    /// bundle id: must not resume.
    func testWorkspaceTerminationOfUnrelatedBundleIdIsIgnored() {
        let center = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        var changeCount = 0
        let suspendedExp = expectation(description: "suspended")
        let unwantedResume = expectation(description: "unwanted resume")
        unwantedResume.isInverted = true
        let bridge = LaunchPadPresenceBridge(
            center: center, workspaceCenter: workspaceCenter, bundleId: "com.example.not-launchpad"
        ) { suspended in
            changeCount += 1
            if suspended { suspendedExp.fulfill() } else { unwantedResume.fulfill() }
        }

        center.post(name: LaunchPadPresenceBridge.didShow, object: nil)
        wait(for: [suspendedExp], timeout: 2.0)

        workspaceCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        wait(for: [unwantedResume], timeout: 0.3)

        XCTAssertEqual(changeCount, 1)
        XCTAssertTrue(bridge.isSuspended)
        bridge.invalidate()
    }

    func testTerminatedBundleIdExtractionIgnoresUnrelatedNotifications() {
        let note = Notification(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: nil)
        XCTAssertNil(LaunchPadPresenceBridge.terminatedBundleId(from: note))
    }
}

import XCTest
import ActionKit
@testable import NotchDeck

/// Exercises `LaunchPadPresenceBridge`'s state handling using the same
/// injectable-`NotificationCenter` seam ActionKit's own
/// `LaunchPadPresenceObserver` tests use (see RadialMenu/app/Tests/
/// ArcusCoreTests/LaunchPadPresenceTests.swift) — deterministic, in-process
/// delivery instead of the real distributed bus.
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

        center.post(name: LaunchPadPresence.didShow, object: nil)
        wait(for: [suspendedExp], timeout: 2.0)
        XCTAssertTrue(bridge.isSuspended)

        center.post(name: LaunchPadPresence.didHide, object: nil)
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

        center.post(name: LaunchPadPresence.didShow, object: nil)
        wait(for: [firstChange], timeout: 2.0)
        center.post(name: LaunchPadPresence.didShow, object: nil) // redundant: no 2nd callback expected

        wait(for: [unwantedSecondChange], timeout: 0.3)
        XCTAssertEqual(changeCount, 1)
        XCTAssertTrue(bridge.isSuspended)
        bridge.invalidate()
    }

    func testProviderTerminatedResumesEvenWithoutDidHide() {
        // Drives the ActionKit observer directly through the same
        // termination-recovery path the workspace-notification hook calls,
        // without needing a real NSRunningApplication.
        let center = NotificationCenter()
        var seen: [Bool] = []
        let suspendedExp = expectation(description: "suspended")
        let resumedExp = expectation(description: "resumed via termination")
        let observer = LaunchPadPresenceObserver(center: center) { suspended in
            seen.append(suspended)
            if suspended { suspendedExp.fulfill() } else { resumedExp.fulfill() }
        }

        center.post(name: LaunchPadPresence.didShow, object: nil)
        wait(for: [suspendedExp], timeout: 2.0)
        observer.providerTerminated()
        wait(for: [resumedExp], timeout: 2.0)

        XCTAssertEqual(seen, [true, false])
        observer.invalidate()
    }

    func testTerminatedBundleIdExtractionIgnoresUnrelatedNotifications() {
        let note = Notification(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: nil)
        XCTAssertNil(LaunchPadPresenceBridge.terminatedBundleId(from: note))
    }
}

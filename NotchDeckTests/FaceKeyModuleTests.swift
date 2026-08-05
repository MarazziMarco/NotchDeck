import XCTest
@testable import NotchDeck

@MainActor
final class FaceKeyModuleTests: XCTestCase {
    func testDescriptorIsAWorkspaceWithNoSensitiveCapabilities() {
        let descriptor = FaceKeyModule.descriptor
        XCTAssertEqual(descriptor.identifier, "built-in.facekey")
        XCTAssertEqual(descriptor.displayName, "FaceKey")
        XCTAssertTrue(descriptor.capabilities.isEmpty, "NotchDeck never handles camera/keys/files")
        XCTAssertTrue(descriptor.surfaces.contains(.workspace))
        XCTAssertTrue(descriptor.surfaces.contains(.settingsSection))
        XCTAssertTrue(descriptor.hasSettings)
        XCTAssertTrue(descriptor.defaultEnabled)
    }

    func testActionsMapToFaceKeyDeepLinks() {
        XCTAssertEqual(FaceKeyModule.Action.verify.url, URL(string: "facekey://verify"))
        XCTAssertEqual(FaceKeyModule.Action.protectFiles.url, URL(string: "facekey://protect"))
        XCTAssertEqual(FaceKeyModule.Action.openContainer.url, URL(string: "facekey://open"))
        XCTAssertEqual(FaceKeyModule.Action.settings.url, URL(string: "facekey://settings"))
        XCTAssertEqual(FaceKeyModule.Action.allCases.count, 4)
    }

    func testPresenceTargetsTheFaceKeyBundleIdentifier() {
        XCTAssertEqual(FaceKeyPresence.bundleIdentifier, "com.marazzimarco.FaceKey")
    }

    func testWorkspaceIsHiddenWhenFaceKeyAppIsNotRunning() {
        // While FaceKey is not running, the workspace stays off even though the
        // toggle defaults to enabled — so quitting FaceKey removes it.
        if !FaceKeyPresence.isRunning {
            var settings = AppSettings()
            settings.moduleEnabled[FaceKeyModule.identifier] = true
            XCTAssertFalse(FaceKeyModule.isEnabled(settings))
        }
    }
}

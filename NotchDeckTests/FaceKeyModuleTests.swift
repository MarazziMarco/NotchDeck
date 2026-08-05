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

    func testInstallationTargetsTheFaceKeyBundleIdentifier() {
        XCTAssertEqual(FaceKeyInstallation.bundleIdentifier, "com.marazzimarco.FaceKey")
    }

    func testWorkspaceIsHiddenWhenFaceKeyAppIsNotInstalled() {
        // On a machine without FaceKey installed, the workspace stays off even
        // though the toggle defaults to enabled.
        if !FaceKeyInstallation.isInstalled {
            var settings = AppSettings()
            settings.moduleEnabled[FaceKeyModule.identifier] = true
            XCTAssertFalse(FaceKeyModule.isEnabled(settings))
        }
    }
}

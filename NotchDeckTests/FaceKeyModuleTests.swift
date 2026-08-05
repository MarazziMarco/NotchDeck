import XCTest
@testable import NotchDeck

@MainActor
final class FaceKeyModuleTests: XCTestCase {
    func testDescriptorDeclaresNoSensitiveCapabilities() {
        let descriptor = FaceKeyModule.descriptor
        XCTAssertEqual(descriptor.identifier, "built-in.facekey")
        XCTAssertEqual(descriptor.displayName, "FaceKey")
        XCTAssertTrue(descriptor.capabilities.isEmpty, "NotchDeck never handles camera/keys/files")
        XCTAssertTrue(descriptor.hasSettings)
        XCTAssertTrue(descriptor.surfaces.contains(.more))
        XCTAssertTrue(descriptor.surfaces.contains(.settingsSection))
    }

    func testActionsMapToFaceKeyDeepLinks() {
        XCTAssertEqual(FaceKeyModule.Action.verify.url, URL(string: "facekey://verify"))
        XCTAssertEqual(FaceKeyModule.Action.protectFiles.url, URL(string: "facekey://protect"))
        XCTAssertEqual(FaceKeyModule.Action.openContainer.url, URL(string: "facekey://open"))
        XCTAssertEqual(FaceKeyModule.Action.settings.url, URL(string: "facekey://settings"))
        XCTAssertEqual(FaceKeyModule.Action.allCases.count, 4)
    }

    func testRegistersIntoTheCommunityRegistryOnTheMoreSurface() throws {
        let registry = CommunityModuleRegistry()
        try registry.register(FaceKeyModule.self)
        XCTAssertNotNil(registry.descriptor(identifier: "built-in.facekey"))
        XCTAssertTrue(
            registry.modules(for: .more).contains { $0.descriptor.identifier == "built-in.facekey" }
        )
    }
}

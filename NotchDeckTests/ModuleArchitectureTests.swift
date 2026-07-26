import XCTest
import SwiftUI
@testable import NotchDeck

/// A second harmless example used only to exercise the registry.
private struct CounterTestModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "com.notchdeck.example.counter",
        displayName: "Counter (Test)", summary: "test", version: "0.1.0",
        author: "tests", category: .example, iconSystemName: "number",
        defaultEnabled: true, surfaces: [.homeCard], capabilities: [])
    init() {}
    func homeCard(context: ModuleContext) -> AnyView? { AnyView(Text("0")) }
}

/// A module declaring one sensitive capability, to prove gating.
private struct CameraTestModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "com.notchdeck.example.cam",
        displayName: "Cam", summary: "s", version: "1.0.0", author: "t",
        category: .media, iconSystemName: "camera",
        defaultEnabled: false, surfaces: [.homeCard], capabilities: [.camera])
    init() {}
}

@MainActor
final class ModuleArchitectureTests: XCTestCase {

    func testExampleModuleDescriptor() {
        let d = UptimeExampleModule.descriptor
        XCTAssertEqual(d.identifier, "com.notchdeck.example.uptime")
        XCTAssertFalse(d.defaultEnabled)                 // examples never ship enabled
        XCTAssertTrue(d.capabilities.isEmpty)            // no sensitive capability
        XCTAssertTrue(d.surfaces.contains(.homeCard))
        XCTAssertEqual(d.category, .example)
    }

    func testUptimeFormatterPure() {
        XCTAssertEqual(UptimeExampleModule.formatUptime(90), "1m")
        XCTAssertEqual(UptimeExampleModule.formatUptime(3 * 3600 + 5 * 60), "3h 5m")
        XCTAssertEqual(UptimeExampleModule.formatUptime(2 * 86_400 + 4 * 3600), "2d 4h")
    }

    func testRegistrationAndLookup() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)
        try reg.register(CounterTestModule.self)
        XCTAssertEqual(reg.modules.count, 2)
        XCTAssertNotNil(reg.descriptor(identifier: "com.notchdeck.example.uptime"))
        XCTAssertNil(reg.descriptor(identifier: "does.not.exist"))
    }

    func testDuplicateIdentifierRejected() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)
        XCTAssertThrowsError(try reg.register(UptimeExampleModule.self)) { err in
            XCTAssertEqual(err as? ModuleRegistryError,
                           .duplicateIdentifier("com.notchdeck.example.uptime"))
        }
        XCTAssertEqual(reg.modules.count, 1)             // not double-registered
    }

    func testCapabilityGating() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)   // no capabilities
        try reg.register(CameraTestModule.self)      // camera only

        let uptime = reg.module(identifier: "com.notchdeck.example.uptime")!
        XCTAssertFalse(uptime.context.has(.camera))
        XCTAssertFalse(uptime.context.has(.agentApprovalEvents))
        XCTAssertTrue(uptime.context.sensitiveCapabilities.isEmpty)

        let cam = reg.module(identifier: "com.notchdeck.example.cam")!
        XCTAssertTrue(cam.context.has(.camera))
        XCTAssertFalse(cam.context.has(.screenRecording))    // NOT granted anything else
        XCTAssertEqual(cam.context.sensitiveCapabilities, [.camera])
    }

    func testDefaultEnabledState() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)   // defaultEnabled false
        try reg.register(CounterTestModule.self)     // defaultEnabled true
        XCTAssertFalse(reg.isEnabled("com.notchdeck.example.uptime"))
        XCTAssertTrue(reg.isEnabled("com.notchdeck.example.counter"))
        XCTAssertEqual(reg.enabledModules.map { $0.descriptor.identifier },
                       ["com.notchdeck.example.counter"])
        reg.setEnabled(true, identifier: "com.notchdeck.example.uptime")
        XCTAssertTrue(reg.isEnabled("com.notchdeck.example.uptime"))
    }

    func testDeterministicOrdering() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(CounterTestModule.self)     // ...counter
        try reg.register(UptimeExampleModule.self)   // ...uptime
        // Registration order preserved.
        XCTAssertEqual(reg.modules.map { $0.descriptor.identifier },
                       ["com.notchdeck.example.counter", "com.notchdeck.example.uptime"])
        // And a stable id-sorted view for Settings.
        XCTAssertEqual(reg.sortedByIdentifier.map { $0.descriptor.identifier },
                       ["com.notchdeck.example.counter", "com.notchdeck.example.uptime"])
    }

    func testIdentifierAliasMigration() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)
        reg.addAlias(from: "com.old.uptime", to: "com.notchdeck.example.uptime")
        XCTAssertNotNil(reg.module(identifier: "com.old.uptime"))
    }

    func testSurfaceFiltering() throws {
        let reg = CommunityModuleRegistry()
        try reg.register(UptimeExampleModule.self)
        XCTAssertEqual(reg.modules(for: .homeCard).count, 1)
        XCTAssertEqual(reg.modules(for: .compactLiveActivity).count, 0)
    }
}

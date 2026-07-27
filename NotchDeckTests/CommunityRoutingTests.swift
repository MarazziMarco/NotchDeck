import XCTest
@testable import NotchDeck

/// Central rule: ModuleSource.community → More only, never Home. Plus Home-layout
/// normalization/migration of stale Community placement.
final class CommunityRoutingTests: XCTestCase {

    private func desc(_ id: String, surfaces: Set<ModuleSurface>) -> ModuleDescriptor {
        ModuleDescriptor(identifier: id, displayName: id, summary: "s", version: "1.0.0",
                         author: "a", category: .system, iconSystemName: "gear",
                         defaultEnabled: false, surfaces: surfaces, capabilities: [], hasSettings: true)
    }

    // MARK: Central routing (tests 36, 37, 43, 44)

    func testCommunityAlwaysResolvesToMoreNeverHome() {
        // Even with an obsolete `.homeCard` declaration.
        let d = desc("community.x", surfaces: [.homeCard, .settingsSection])
        XCTAssertTrue(ModuleSurfaceRouting.rendersInMore(d, source: .community))
        XCTAssertFalse(ModuleSurfaceRouting.rendersInHome(d, source: .community))
    }

    func testSystemPulseDescriptorRoutesToMore() {
        let d = SystemPulseModule.descriptor
        XCTAssertFalse(d.surfaces.contains(.homeCard), "System Pulse no longer declares Home")
        XCTAssertTrue(d.surfaces.contains(.more))
        XCTAssertFalse(ModuleSurfaceRouting.rendersInHome(d, source: .community))
        XCTAssertTrue(ModuleSurfaceRouting.rendersInMore(d, source: .community))
    }

    func testBuiltInHomeModuleStillEligibleForHome() {
        let d = desc("quickNote", surfaces: [.homeCard])
        XCTAssertTrue(ModuleSurfaceRouting.rendersInHome(d, source: .builtIn))
        XCTAssertFalse(ModuleSurfaceRouting.rendersInMore(d, source: .builtIn))
    }

    func testAgentsWorkspaceNeverInMoreOrHome() {
        let d = AgentsModule.descriptor
        XCTAssertFalse(ModuleSurfaceRouting.rendersInMore(d, source: .builtIn))
        XCTAssertFalse(ModuleSurfaceRouting.rendersInHome(d, source: .builtIn))
    }

    func testCatalogEntryHomeFlagExcludesCommunity() {
        let entry = ModuleCatalogEntry(descriptor: desc("community.y", surfaces: [.homeCard]),
                                       source: .community)
        XCTAssertFalse(entry.isHomeModule)
        XCTAssertTrue(entry.isMoreModule)
    }

    // MARK: Home-layout normalization / migration (tests 41, 42; message 3,4)

    private let eligible: Set<String> = ["quickNote", "nowPlaying", "fileShelf", "mirror"]

    func testStaleCommunityIDRemovedFromHomeLayout() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "community.system-pulse", "mirror"]
        s.editorialHidden = ["community.system-pulse"]
        s.homeSizes["community.system-pulse"] = .large
        XCTAssertTrue(HomeLayoutNormalizer.needsNormalization(s, eligible: eligible))
        HomeLayoutNormalizer.normalize(&s, eligible: eligible)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "mirror"], "community removed, built-in order preserved")
        XCTAssertFalse(s.editorialHidden.contains("community.system-pulse"))
        XCTAssertNil(s.homeSizes["community.system-pulse"])
    }

    func testMigrationDoesNotReorderBuiltInHomeModules() {
        var s = AppSettings()
        s.editorialOrder = ["mirror", "quickNote", "community.system-pulse", "nowPlaying", "fileShelf"]
        HomeLayoutNormalizer.normalize(&s, eligible: eligible)
        XCTAssertEqual(s.editorialOrder, ["mirror", "quickNote", "nowPlaying", "fileShelf"])
    }

    func testNormalizationRemovesDuplicatesAndUnknownIDs() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "quickNote", "obsolete.thing", "built-in.agents", "mirror"]
        HomeLayoutNormalizer.normalize(&s, eligible: eligible)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "mirror"], "dedup + drop unknown/workspace")
    }

    func testNormalizationCannotAddSystemPulseBack() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "mirror"]
        HomeLayoutNormalizer.normalize(&s, eligible: eligible)
        XCTAssertFalse(s.editorialOrder!.contains("community.system-pulse"))
    }

    func testCleanLayoutNeedsNoNormalization() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "mirror"]
        XCTAssertFalse(HomeLayoutNormalizer.needsNormalization(s, eligible: eligible))
    }

    // MARK: Enable/disable preserves settings (tests 38–40; message 6–8)

    func testSystemPulseSettingsSurviveDisableReEnable() {
        var s = AppSettings()
        s.systemPulse.refreshInterval = .s60
        s.systemPulse.showStorage = false
        // Disable then re-enable via the authoritative moduleEnabled bridge.
        ModuleEnablement.setEnabled(SystemPulseModule.descriptor.identifier, false,
                                    isHomeModule: false, defaultOrder: [], in: &s)
        ModuleEnablement.setEnabled(SystemPulseModule.descriptor.identifier, true,
                                    isHomeModule: false, defaultOrder: [], in: &s)
        XCTAssertEqual(s.systemPulse.refreshInterval, .s60, "metric settings preserved")
        XCTAssertFalse(s.systemPulse.showStorage)
    }

    func testEnablingCommunityDoesNotAddHomePlacement() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "mirror"]
        // ModulesScreen passes isHomeModule from the catalog entry (false for community).
        ModuleEnablement.setEnabled(SystemPulseModule.descriptor.identifier, true,
                                    isHomeModule: false, defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "mirror"], "never gains a Home slot")
    }
}

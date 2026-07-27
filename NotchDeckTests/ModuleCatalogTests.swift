import XCTest
@testable import NotchDeck

/// Catalogue + enablement bridge. Pure over descriptors/AppSettings — no panel.
final class ModuleCatalogTests: XCTestCase {

    private func desc(_ id: String, _ name: String, source community: Bool = false,
                     home: Bool = true, defaultEnabled: Bool = true) -> ModuleDescriptor {
        ModuleDescriptor(identifier: id, displayName: name, summary: "\(name) summary",
                         version: "1.0.0", author: community ? "Contributors" : "NotchDeck",
                         category: .system, iconSystemName: "gear", defaultEnabled: defaultEnabled,
                         surfaces: home ? [.homeCard] : [.settingsSection], capabilities: [], hasSettings: true)
    }

    private func catalog(includeExample: Bool = false) -> ModuleCatalog {
        ModuleCatalog(
            builtIn: [desc("mirror", "Mirror"), desc("quickNote", "Quick Note")],
            community: [desc("community.system-pulse", "System Pulse", source: true, defaultEnabled: false)],
            example: [desc("example.uptime", "Uptime Example", source: true, defaultEnabled: false)],
            includeExample: includeExample)
    }

    // MARK: Appearance / ordering / dedup

    func testBuiltInThenCommunityOrdering() {
        let sources = catalog().entries.map(\.source)
        XCTAssertEqual(sources, [.builtIn, .builtIn, .community])
    }

    func testDeterministicAlphabeticalWithinSource() {
        // "Mirror" > "Quick Note"? sorted by displayName: "Mirror", "Quick Note".
        let builtIn = catalog().entries.filter { $0.source == .builtIn }.map(\.descriptor.displayName)
        XCTAssertEqual(builtIn, ["Mirror", "Quick Note"])
    }

    func testExampleHiddenByDefaultShownWhenIncluded() {
        XCTAssertFalse(catalog().entries.contains { $0.source == .example })
        XCTAssertTrue(catalog(includeExample: true).entries.contains { $0.id == "example.uptime" })
    }

    func testDuplicateIdentifierRejected() {
        let c = ModuleCatalog(builtIn: [desc("dup", "A")], community: [desc("dup", "B")],
                              example: [], includeExample: false)
        XCTAssertEqual(c.entries.count, 1, "second registration of a duplicate id is dropped")
        XCTAssertEqual(c.entries.first?.source, .builtIn)
    }

    func testEntryLookupByID() {
        XCTAssertEqual(catalog().entry(id: "community.system-pulse")?.descriptor.displayName, "System Pulse")
        XCTAssertNil(catalog().entry(id: "nope"))
    }

    // MARK: Search + filter

    func testSearchMatchesNameAndSummary() {
        let c = catalog()
        XCTAssertEqual(c.filtered(search: "pulse", filter: .all) { _ in true }.map(\.id),
                       ["community.system-pulse"])
        XCTAssertEqual(c.filtered(search: "summary", filter: .all) { _ in true }.count, 3)
    }

    func testFilterBySource() {
        let c = catalog()
        XCTAssertTrue(c.filtered(search: "", filter: .builtIn) { _ in true }.allSatisfy { $0.source == .builtIn })
        XCTAssertTrue(c.filtered(search: "", filter: .community) { _ in true }.allSatisfy { $0.source == .community })
    }

    func testFilterByEnabled() {
        let c = catalog()
        let enabledIDs: Set<String> = ["mirror"]
        let out = c.filtered(search: "", filter: .enabled) { enabledIDs.contains($0.id) }
        XCTAssertEqual(out.map(\.id), ["mirror"])
    }

    func testEmptySearchReturnsAll() {
        XCTAssertEqual(catalog().filtered(search: "   ", filter: .all) { _ in true }.count, 3)
    }

    // MARK: Enablement bridge (one source of truth)

    func testIsEnabledDefaultsToDescriptor() {
        var s = AppSettings()
        XCTAssertFalse(ModuleEnablement.isEnabled("community.system-pulse", defaultEnabled: false, settings: s))
        s.moduleEnabled["community.system-pulse"] = true
        XCTAssertTrue(ModuleEnablement.isEnabled("community.system-pulse", defaultEnabled: false, settings: s))
    }

    func testEnableHomeModuleAppendsPlacementOnce() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "mirror"]
        ModuleEnablement.setEnabled("community.system-pulse", true, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "mirror", "community.system-pulse"])
        // Toggling again does not duplicate.
        ModuleEnablement.setEnabled("community.system-pulse", true, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder?.filter { $0 == "community.system-pulse" }.count, 1)
    }

    func testDisablePreservesOrderAndSize() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "community.system-pulse", "mirror"]
        s.homeSizes["community.system-pulse"] = .large
        ModuleEnablement.setEnabled("community.system-pulse", false, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.moduleEnabled["community.system-pulse"], false)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "community.system-pulse", "mirror"], "placement preserved")
        XCTAssertEqual(s.homeSizes["community.system-pulse"], .large, "size preserved for re-enable")
    }

    func testReEnableRestoresPriorPlacement() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "community.system-pulse", "mirror"]
        ModuleEnablement.setEnabled("community.system-pulse", false, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        ModuleEnablement.setEnabled("community.system-pulse", true, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "community.system-pulse", "mirror"])
    }

    func testEnableRemovesFromHidden() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "community.system-pulse"]
        s.editorialHidden = ["community.system-pulse"]
        ModuleEnablement.setEnabled("community.system-pulse", true, isHomeModule: true,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertFalse(s.editorialHidden.contains("community.system-pulse"))
    }

    func testNonHomeModuleDoesNotTouchOrder() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote"]
        ModuleEnablement.setEnabled("settings.only", true, isHomeModule: false,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder, ["quickNote"])
        XCTAssertEqual(s.moduleEnabled["settings.only"], true)
    }

    // MARK: Legacy adapter

    func testLegacyAdapterMapsCapabilities() {
        XCTAssertEqual(LegacyModuleAdapter.capabilities(for: "mirror"), [.camera])
        XCTAssertEqual(LegacyModuleAdapter.capabilities(for: "downloads"), [.downloadsAccess])
        XCTAssertTrue(LegacyModuleAdapter.capabilities(for: "quickNote").isEmpty)
    }

    @MainActor
    func testCommunityModuleRegistryRejectsDuplicate() {
        let reg = CommunityModuleRegistry()
        XCTAssertNoThrow(try reg.register(SystemPulseModule.self))
        XCTAssertThrowsError(try reg.register(SystemPulseModule.self)) { err in
            XCTAssertEqual(err as? ModuleRegistryError, .duplicateIdentifier("community.system-pulse"))
        }
    }

    @MainActor
    func testSystemPulseDescriptorContract() {
        let d = SystemPulseModule.descriptor
        XCTAssertEqual(d.identifier, "community.system-pulse")
        XCTAssertEqual(d.version, "1.0.0")
        XCTAssertFalse(d.defaultEnabled)
        XCTAssertTrue(d.capabilities.isEmpty, "no sensitive capabilities")
        XCTAssertTrue(d.surfaces.contains(.homeCard))
    }
}

import XCTest
@testable import NotchDeck

/// More Module Library + dashboard: eligibility, independent persistence,
/// deterministic grid, and strict separation from Home.
final class MoreLayoutTests: XCTestCase {

    private func desc(_ id: String, source: ModuleSource = .community,
                      sizes: [MoreModuleSize] = [.wide, .large],
                      def: MoreModuleSize = .wide) -> MoreModuleDescriptor {
        MoreModuleDescriptor(id: id, name: id, summary: "s", iconSystemName: "gear",
                             source: source, supportedSizes: sizes, defaultSize: def)
    }

    // MARK: Size / span model (tests 14, 15)

    func testSizeSpans() {
        XCTAssertEqual(MoreModuleSize.compact.w, 1); XCTAssertEqual(MoreModuleSize.compact.h, 1)
        XCTAssertEqual(MoreModuleSize.wide.w, 2);    XCTAssertEqual(MoreModuleSize.wide.h, 1)
        XCTAssertEqual(MoreModuleSize.large.w, 2);   XCTAssertEqual(MoreModuleSize.large.h, 2)
    }

    func testDescriptorNormalizesUnsupportedSize() {
        let d = desc("x", sizes: [.wide], def: .wide)
        XCTAssertEqual(d.normalizedSize(.large), .wide, "unsupported size falls back to default")
        XCTAssertEqual(d.normalizedSize(nil), .wide)
    }

    // MARK: Normalizer (tests 13, 18, 19)

    private let defs = [
        MoreModuleDescriptor(id: "community.system-pulse", name: "System Pulse", summary: "",
                             iconSystemName: "waveform", source: .community,
                             supportedSizes: [.wide, .large], defaultSize: .wide),
        MoreModuleDescriptor(id: "battery", name: "Battery", summary: "", iconSystemName: "battery.100",
                             source: .builtIn, supportedSizes: [.compact, .wide], defaultSize: .compact),
    ]

    func testNormalizeDropsUnknownAndDedups() {
        var layout = MoreLayoutSettings(order: ["battery", "battery", "ghost", "community.system-pulse"],
                                        sizes: ["ghost": .large, "battery": .large])
        MoreLayoutNormalizer.normalize(&layout, definitions: defs)
        XCTAssertEqual(layout.order, ["battery", "community.system-pulse"], "dedup + drop unknown, keep order")
        XCTAssertNil(layout.sizes["ghost"])
        XCTAssertEqual(layout.sizes["battery"], .compact, "falls back to the declared default size")
    }

    func testNormalizeAppendsNewlyEligible() {
        var layout = MoreLayoutSettings(order: ["battery"], sizes: [:])
        MoreLayoutNormalizer.normalize(&layout, definitions: defs)
        XCTAssertEqual(layout.order, ["battery", "community.system-pulse"])
    }

    func testDefaultOrderIsCommunityThenBuiltIn() {
        XCTAssertEqual(MoreLayoutNormalizer.defaultOrder(defs), ["community.system-pulse", "battery"])
    }

    func testPlacedOrderFiltersByEnabled() {
        var layout = MoreLayoutSettings(order: ["community.system-pulse", "battery"], sizes: [:])
        MoreLayoutNormalizer.normalize(&layout, definitions: defs)
        let placed = MoreLayoutNormalizer.placedOrder(layout, definitions: defs) { $0 == "battery" }
        XCTAssertEqual(placed, ["battery"])
    }

    func testUnknownStoredIDsDoNotCrash() {
        var layout = MoreLayoutSettings(order: ["nope", "gone"], sizes: ["nope": .compact])
        MoreLayoutNormalizer.normalize(&layout, definitions: defs)
        XCTAssertEqual(layout.order, ["community.system-pulse", "battery"])
    }

    // MARK: Grid solver (test 15, 16)

    func testCompactWideLargeProduceValidGrid() {
        let items = [MoreGridSolver.Item(id: "a", size: .compact),
                     MoreGridSolver.Item(id: "b", size: .compact),
                     MoreGridSolver.Item(id: "w", size: .wide),
                     MoreGridSolver.Item(id: "L", size: .large)]
        let result = MoreGridSolver.solve(items)
        // No two cells overlap.
        for i in result.cells.indices { for j in (i+1)..<result.cells.count {
            XCTAssertFalse(MoreGridSolver.overlaps(result.cells[i], result.cells[j]))
        }}
        // a,b share the first row; wide spans 2 columns.
        XCTAssertEqual(result.cells.first { $0.id == "w" }?.w, 2)
        XCTAssertEqual(result.cells.first { $0.id == "L" }?.h, 2)
    }

    func testGridDeterministic() {
        let items = [MoreGridSolver.Item(id: "L", size: .large),
                     MoreGridSolver.Item(id: "a", size: .compact),
                     MoreGridSolver.Item(id: "w", size: .wide)]
        XCTAssertEqual(MoreGridSolver.solve(items), MoreGridSolver.solve(items))
    }

    // MARK: Eligibility — More only, never Home (tests 4, 5, 6, 28)

    func testSystemPulseIsMoreOnlyNeverHome() {
        let d = SystemPulseModule.descriptor
        XCTAssertTrue(ModuleSurfaceRouting.rendersInMore(d, source: .community))
        XCTAssertFalse(ModuleSurfaceRouting.rendersInHome(d, source: .community))
    }

    func testHomeOnlyBuiltInExcludedFromMore() {
        // A built-in Home module (quickNote group == .home) is not More-eligible.
        let d = LegacyModuleAdapter.descriptor(id: "quickNote", name: "Quick Note",
                                               icon: "note.text", defaultEnabled: true, hasSettings: false)
        XCTAssertFalse(ModuleSurfaceRouting.rendersInMore(d, source: .builtIn))
    }

    // MARK: Catalog from registries (tests 7, 27) + independence (22, 23)

    @MainActor func testCatalogDerivedFromRegistries() {
        let store = SettingsStore.inMemory()
        let registry = ModuleRegistry(modules: [BatteryModule(), QuickNoteModule()], settings: store)
        let community = CommunityModuleRegistry()
        _ = try? community.register(SystemPulseModule.self)
        let ids = MoreCatalog.descriptors(registry: registry, community: community).map(\.id)
        XCTAssertTrue(ids.contains("community.system-pulse"), "community module present")
        XCTAssertTrue(ids.contains("battery"), "built-in .more module present")
        XCTAssertFalse(ids.contains("quickNote"), "Home-only built-in excluded")
        // Community source first.
        XCTAssertEqual(ids.first, "community.system-pulse")
    }

    @MainActor func testMoreEditDoesNotMutateHome() {
        let store = SettingsStore.inMemory()
        store.settings.editorialOrder = ["quickNote", "mirror"]
        store.settings.homeSizes = ["quickNote": .large]
        let homeOrderBefore = store.settings.editorialOrder
        let homeSizesBefore = store.settings.homeSizes
        store.updateMoreLayout(definitions: defs) {
            $0.moduleEnabled["community.system-pulse"] = true
            $0.moreLayout.sizes["community.system-pulse"] = .large
        }
        XCTAssertEqual(store.settings.editorialOrder, homeOrderBefore, "Home order untouched")
        XCTAssertEqual(store.settings.homeSizes, homeSizesBefore, "Home sizes untouched")
        XCTAssertEqual(store.settings.moreLayout.sizes["community.system-pulse"], .large)
    }

    @MainActor func testHomeEditDoesNotMutateMore() {
        let store = SettingsStore.inMemory()
        store.settings.moreLayout.order = ["community.system-pulse"]
        store.settings.moreLayout.sizes = ["community.system-pulse": .wide]
        let moreBefore = store.settings.moreLayout
        store.settings.editorialOrder = ["quickNote"]   // a Home mutation
        XCTAssertEqual(store.settings.moreLayout, moreBefore, "More layout untouched by Home edit")
    }

    // MARK: Add / remove placement (tests 8, 9, 10)

    @MainActor func testAddThenRemoveTogglesPlacement() {
        let store = SettingsStore.inMemory()
        store.updateMoreLayout(definitions: defs) { $0.moduleEnabled["community.system-pulse"] = true }
        XCTAssertEqual(store.settings.moduleEnabled["community.system-pulse"], true)
        // Duplicate add does not duplicate the order entry.
        store.updateMoreLayout(definitions: defs) { $0.moduleEnabled["community.system-pulse"] = true }
        XCTAssertEqual(store.settings.moreLayout.order?.filter { $0 == "community.system-pulse" }.count, 1)
        store.updateMoreLayout(definitions: defs) { $0.moduleEnabled["community.system-pulse"] = false }
        XCTAssertEqual(store.settings.moduleEnabled["community.system-pulse"], false)
        // Size/order preserved for return.
        XCTAssertTrue(store.settings.moreLayout.order?.contains("community.system-pulse") ?? false)
    }

    func testPlacementIsMoreSpecificAndIndependentFromGlobalEnablement() {
        var layout = MoreLayoutSettings(
            order: ["community.system-pulse", "battery"],
            sizes: [:],
            placedIDs: ["battery"]
        )
        MoreLayoutNormalizer.normalize(&layout, definitions: defs)
        XCTAssertEqual(
            MoreLayoutNormalizer.placedOrder(layout, definitions: defs),
            ["battery"]
        )
        MoreLayoutEditor.add("community.system-pulse", to: &layout, definitions: defs)
        MoreLayoutEditor.add("community.system-pulse", to: &layout, definitions: defs)
        XCTAssertEqual(layout.placedIDs?.filter { $0 == "community.system-pulse" }.count, 1)
        MoreLayoutEditor.remove("community.system-pulse", from: &layout, definitions: defs)
        XCTAssertFalse(layout.placedIDs?.contains("community.system-pulse") ?? true)
        XCTAssertTrue(layout.order?.contains("community.system-pulse") ?? false)
    }

    func testRestoreDefaultsUsesDescriptorPlacementMetadata() {
        let defaults = [
            MoreModuleDescriptor(
                id: "system",
                name: "System",
                summary: "",
                iconSystemName: "waveform",
                source: .community,
                supportedSizes: [.wide],
                defaultSize: .wide,
                defaultPlaced: true,
                defaultOrder: 0
            ),
            MoreModuleDescriptor(
                id: "optional",
                name: "Optional",
                summary: "",
                iconSystemName: "puzzlepiece",
                source: .community,
                supportedSizes: [.wide],
                defaultSize: .wide,
                defaultPlaced: false,
                defaultOrder: 1
            )
        ]
        var layout = MoreLayoutSettings(
            order: ["optional"],
            sizes: ["optional": .wide],
            placedIDs: ["optional"]
        )
        MoreLayoutEditor.restoreDefaults(&layout, definitions: defaults)
        XCTAssertEqual(layout.order, ["system", "optional"])
        XCTAssertEqual(layout.placedIDs, ["system"])
    }

    func testVerticalGridNeverWrapsOntoOverlappingPages() {
        let items = (0..<401).map {
            MoreGridSolver.Item(id: "\($0)", size: .compact)
        }
        let result = MoreGridSolver.solve(items)
        XCTAssertTrue(result.cells.allSatisfy { $0.page == 0 })
        let locations = Set(result.cells.map { "\($0.col):\($0.row)" })
        XCTAssertEqual(locations.count, items.count)
    }

    @MainActor func testMoreOrderSizeAndPlacementPersistImmediately() throws {
        let suite = "more-persistence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.updateMoreLayout(definitions: defs) {
            MoreLayoutEditor.add("community.system-pulse", to: &$0.moreLayout, definitions: defs)
            $0.moreLayout.order = ["battery", "community.system-pulse"]
            $0.moreLayout.sizes["community.system-pulse"] = .large
        }

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.moreLayout.order, ["battery", "community.system-pulse"])
        XCTAssertEqual(reloaded.settings.moreLayout.sizes["community.system-pulse"], .large)
        XCTAssertTrue(
            reloaded.settings.moreLayout.placedIDs?.contains("community.system-pulse") == true
        )
    }
}

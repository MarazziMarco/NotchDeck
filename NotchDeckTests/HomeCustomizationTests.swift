import XCTest
@testable import NotchDeck

@MainActor
final class HomeCustomizationTests: XCTestCase {
    private let current: [HomeModuleDefinition] = [
        .init(id: "quickNote", name: "Quick Note", icon: "note.text",
              defaultPriority: 50, defaultVisible: true,
              supportedSizes: [.narrow, .standard, .prominent], defaultSize: .standard),
        .init(id: "nowPlaying", name: "Now Playing", icon: "music.note",
              defaultPriority: 60, defaultVisible: true,
              supportedSizes: [.narrow, .standard, .prominent], defaultSize: .standard),
        .init(id: "fileShelf", name: "File Shelf", icon: "tray.full",
              defaultPriority: 20, defaultVisible: true,
              supportedSizes: [.narrow, .standard, .prominent], defaultSize: .narrow),
        .init(id: "mirror", name: "Mirror", icon: "web.camera",
              defaultPriority: 30, defaultVisible: true,
              supportedSizes: [.narrow, .standard], defaultSize: .standard),
    ]

    private func normalized(_ source: AppSettings = AppSettings(),
                            definitions: [HomeModuleDefinition]? = nil) -> AppSettings {
        var settings = source
        HomeLayoutNormalizer.normalize(&settings, definitions: definitions ?? current)
        return settings
    }

    func testEligibilityUsesStableBuiltInHomeMetadata() {
        let modules: [NotchModule] = [
            ClipboardModule(), FileShelfModule(), MirrorModule(), PomodoroModule(),
            QuickNoteModule(), NowPlayingModule(), DownloadsModule(), ScreenshotModule(),
            BatteryModule(),
        ]
        XCTAssertEqual(HomeModuleEligibility.definitions(from: modules).map(\.id),
                       ["quickNote", "nowPlaying", "fileShelf", "mirror"])
        XCTAssertTrue(HomeModuleEligibility.definitions(from: modules).allSatisfy(\.defaultVisible))
    }

    func testCommunitySystemPulseAgentsExamplesAndMoreAreExcluded() {
        XCTAssertFalse(HomeModuleEligibility.isEligible(
            source: .community, declaredGroup: .home, surfaces: [.homeCard]))
        XCTAssertFalse(HomeModuleEligibility.isEligible(
            source: .builtIn, declaredGroup: nil, surfaces: [.workspace]))
        XCTAssertFalse(HomeModuleEligibility.isEligible(
            source: .example, declaredGroup: .home, surfaces: [.homeCard]))
        XCTAssertFalse(HomeModuleEligibility.isEligible(
            source: .builtIn, declaredGroup: .more, surfaces: [.homeCard]))
        XCTAssertFalse(HomeModuleEligibility.isEligible(
            source: .community, declaredGroup: .more, surfaces: SystemPulseModule.descriptor.surfaces))
        XCTAssertTrue(HomeModuleEligibility.isEligible(
            source: .builtIn, declaredGroup: .home, surfaces: [.homeCard]))
    }

    func testOrderVisibilityAndSizeMutationsPersistInAuthoritativeSettings() {
        var settings = normalized()
        HomeLayoutNormalizer.move("mirror", before: "quickNote", in: &settings, definitions: current)
        HomeLayoutNormalizer.setVisible(false, id: "fileShelf", in: &settings, definitions: current)
        HomeLayoutNormalizer.setSize(.prominent, id: "quickNote", in: &settings, definitions: current)

        XCTAssertEqual(settings.editorialOrder, ["mirror", "quickNote", "nowPlaying", "fileShelf"])
        XCTAssertFalse(HomeLayoutNormalizer.isVisible("fileShelf", in: settings, definitions: current))
        XCTAssertFalse(settings.moduleEnabled["fileShelf"] ?? true)
        XCTAssertEqual(HomeLayoutNormalizer.size("quickNote", in: settings, definitions: current), .prominent)
    }

    func testHiddenModuleRetainsSizeAndRelativeOrderWhenReenabled() {
        var settings = normalized()
        HomeLayoutNormalizer.move("mirror", before: "quickNote", in: &settings, definitions: current)
        HomeLayoutNormalizer.setSize(.narrow, id: "mirror", in: &settings, definitions: current)
        let orderBefore = settings.editorialOrder

        HomeLayoutNormalizer.setVisible(false, id: "mirror", in: &settings, definitions: current)
        HomeLayoutNormalizer.setVisible(true, id: "mirror", in: &settings, definitions: current)

        XCTAssertEqual(settings.editorialOrder, orderBefore)
        XCTAssertEqual(HomeLayoutNormalizer.size("mirror", in: settings, definitions: current), .narrow)
        XCTAssertEqual(HomeLayoutNormalizer.visibleOrder(in: settings, definitions: current).first, "mirror")
    }

    func testLegacyHomeVisibilityMigratesToAuthoritativeEnablement() {
        var settings = AppSettings()
        settings.editorialHidden = ["mirror", "community.system-pulse", "obsolete"]

        settings = normalized(settings)

        XCTAssertTrue(settings.editorialHidden.isEmpty)
        XCTAssertFalse(settings.moduleEnabled["mirror"] ?? true)
        XCTAssertFalse(HomeLayoutNormalizer.isVisible(
            "mirror", in: settings, definitions: current))
    }

    func testDuplicateUnknownCommunityAndWorkspaceIDsAreRemoved() {
        var settings = AppSettings()
        settings.editorialOrder = [
            "quickNote", "quickNote", "obsolete", "community.system-pulse",
            AgentsModule.identifier, "mirror",
        ]
        settings.editorialHidden = ["community.system-pulse", "obsolete"]
        settings.editorialWidths = [
            "quickNote": .standard, "community.system-pulse": .prominent, "obsolete": .narrow,
        ]
        settings.homeFavorites = ["mirror", "mirror", "community.system-pulse"]
        settings.homeSizes = ["obsolete": .large, "mirror": .small]
        settings.widgetPlacements["regular"] = [
            .init(moduleID: "mirror", order: 4, size: .small),
            .init(moduleID: "mirror", order: 2, size: .medium),
            .init(moduleID: "community.system-pulse", order: 0, size: .large),
        ]

        settings = normalized(settings)

        XCTAssertEqual(settings.editorialOrder, ["quickNote", "mirror", "nowPlaying", "fileShelf"])
        XCTAssertTrue(settings.editorialHidden.isEmpty)
        XCTAssertEqual(Set(settings.editorialWidths.keys), Set(current.map(\.id)))
        XCTAssertEqual(settings.homeFavorites, ["mirror"])
        XCTAssertEqual(settings.homeSizes, ["mirror": .small])
        XCTAssertEqual(settings.widgetPlacements["regular"]?.map(\.moduleID), ["mirror"])
    }

    func testNewEligibleBuiltInsAreAppendedDeterministically() {
        let futureA = HomeModuleDefinition(
            id: "future.a", name: "Future A", icon: "a.circle", defaultPriority: 80,
            defaultVisible: true, supportedSizes: [.standard], defaultSize: .standard)
        let futureB = HomeModuleDefinition(
            id: "future.b", name: "Future B", icon: "b.circle", defaultPriority: 70,
            defaultVisible: true, supportedSizes: [.standard], defaultSize: .standard)
        var settings = AppSettings()
        settings.editorialOrder = ["mirror", "quickNote"]

        settings = normalized(settings, definitions: current + [futureA, futureB])

        XCTAssertEqual(settings.editorialOrder,
                       ["mirror", "quickNote", "nowPlaying", "fileShelf", "future.b", "future.a"])
    }

    func testUnsupportedSizesNormalizeToSupportedDefault() {
        var settings = AppSettings()
        settings.editorialWidths["mirror"] = .prominent

        settings = normalized(settings)

        XCTAssertEqual(settings.editorialWidths["mirror"], .standard)
        XCTAssertEqual(HomeLayoutNormalizer.size("mirror", in: settings, definitions: current), .standard)
    }

    func testResetRestoresDocumentedDefaultsWithoutResettingUnrelatedSettings() {
        var settings = normalized()
        settings.homeLayoutPreset = .spacious
        settings.showHomeDividers = false
        settings.systemPulse.refreshInterval = .s60
        settings.moduleEnabled["mirror"] = false
        HomeLayoutNormalizer.move("mirror", before: "quickNote", in: &settings, definitions: current)
        HomeLayoutNormalizer.setVisible(false, id: "nowPlaying", in: &settings, definitions: current)
        HomeLayoutNormalizer.setSize(.prominent, id: "quickNote", in: &settings, definitions: current)

        HomeLayoutNormalizer.reset(&settings, definitions: current)

        XCTAssertEqual(settings.editorialOrder, EditorialHomeLayout.defaultOrder)
        XCTAssertEqual(HomeLayoutNormalizer.visibleOrder(in: settings, definitions: current),
                       EditorialHomeLayout.defaultOrder)
        XCTAssertEqual(settings.editorialWidths["quickNote"], .standard)
        XCTAssertEqual(settings.editorialWidths["fileShelf"], .narrow)
        XCTAssertEqual(settings.homeLayoutPreset, .spacious)
        XCTAssertFalse(settings.showHomeDividers)
        XCTAssertEqual(settings.systemPulse.refreshInterval, .s60)
        XCTAssertTrue(settings.moduleEnabled["mirror"] ?? false)
    }

    func testRepeatedEditingAndNormalizationNeverCreatesDuplicates() {
        var settings = normalized()
        for _ in 0..<5 {
            HomeLayoutNormalizer.move("mirror", before: "quickNote", in: &settings, definitions: current)
            HomeLayoutNormalizer.setVisible(false, id: "mirror", in: &settings, definitions: current)
            HomeLayoutNormalizer.setVisible(true, id: "mirror", in: &settings, definitions: current)
            HomeLayoutNormalizer.normalize(&settings, definitions: current)
        }
        XCTAssertEqual(settings.editorialOrder?.count, Set(settings.editorialOrder ?? []).count)
        XCTAssertEqual(Set(settings.editorialOrder ?? []), Set(current.map(\.id)))
    }

    func testAllHiddenProducesRecoveryStateWithoutReenablingModules() {
        var settings = normalized()
        for definition in current {
            HomeLayoutNormalizer.setVisible(false, id: definition.id,
                                            in: &settings, definitions: current)
        }

        XCTAssertTrue(HomeLayoutNormalizer.visibleOrder(in: settings, definitions: current).isEmpty)
        XCTAssertEqual(HomeEmptyState.title, "Your Home is empty")
        XCTAssertEqual(HomeEmptyState.message, "Choose which utilities appear here.")
        XCTAssertTrue(current.allSatisfy {
            !HomeLayoutNormalizer.isVisible($0.id, in: settings, definitions: current)
        })
    }

    func testImmediateStoreMutationSurvivesReopenAndRelaunchNormalization() {
        let suite = "HomeCustomizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        first.updateHomeLayout(definitions: current) { settings in
            HomeLayoutNormalizer.move("mirror", before: "quickNote",
                                      in: &settings, definitions: current)
            HomeLayoutNormalizer.setVisible(false, id: "fileShelf",
                                            in: &settings, definitions: current)
            HomeLayoutNormalizer.setSize(.prominent, id: "quickNote",
                                         in: &settings, definitions: current)
        }

        let reopened = SettingsStore(defaults: defaults)
        var relaunched = reopened.settings
        HomeLayoutNormalizer.normalize(&relaunched, definitions: current)

        XCTAssertEqual(relaunched.editorialOrder,
                       ["mirror", "quickNote", "nowPlaying", "fileShelf"])
        XCTAssertFalse(HomeLayoutNormalizer.isVisible("fileShelf", in: relaunched, definitions: current))
        XCTAssertEqual(relaunched.editorialWidths["quickNote"], .prominent)
        XCTAssertEqual(relaunched.editorialOrder?.count, Set(relaunched.editorialOrder ?? []).count)
    }
}

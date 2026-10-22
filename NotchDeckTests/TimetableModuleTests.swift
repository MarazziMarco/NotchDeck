import XCTest
@testable import NotchDeck

@MainActor
final class TimetableModuleTests: XCTestCase {
    private func enabled(_ on: Bool, face: NotchFace = .utilities) -> AppSettings {
        var settings = AppSettings()
        settings.defaultFace = face
        settings.moduleEnabled[TimetableModule.identifier] = on
        return settings
    }

    func testDescriptorIsAWorkspaceWithoutCapabilities() {
        let d = TimetableModule.descriptor
        XCTAssertEqual(d.identifier, "built-in.timetable")
        XCTAssertTrue(d.surfaces.contains(.workspace))
        XCTAssertTrue(d.surfaces.contains(.settingsSection))
        XCTAssertTrue(d.capabilities.isEmpty)
        XCTAssertTrue(d.hasSettings)
        XCTAssertFalse(d.defaultEnabled, "opt-in")
    }

    func testEnablementFollowsTheModuleToggle() {
        XCTAssertFalse(TimetableModule.isEnabled(AppSettings()))
        XCTAssertTrue(TimetableModule.isEnabled(enabled(true)))
    }

    func testWorkspaceIsNeitherHomeNorMore() {
        let entry = ModuleCatalogEntry(descriptor: TimetableModule.descriptor, source: .builtIn)
        XCTAssertFalse(entry.isHomeModule)
        XCTAssertFalse(entry.isMoreModule)
    }

    func testEnablingAddsTheFaceWithoutSwitchingToIt() {
        let store = SettingsStore.inMemory(enabled(false))
        let app = AppState(settings: store)
        XCTAssertFalse(app.availableFaces.contains(.timetable))
        store.settings.moduleEnabled[TimetableModule.identifier] = true
        XCTAssertTrue(app.timetableWorkspaceEnabled)
        XCTAssertTrue(app.availableFaces.contains(.timetable))
        XCTAssertEqual(app.face, .utilities)
    }

    func testDisablingWhileSelectedReturnsToUtilities() {
        let store = SettingsStore.inMemory(enabled(true, face: .timetable))
        let app = AppState(settings: store)
        XCTAssertEqual(app.face, .timetable)
        store.settings.moduleEnabled[TimetableModule.identifier] = false
        XCTAssertEqual(app.face, .utilities)
    }

    func testPersistedFaceIsNormalisedWhenDisabled() {
        let app = AppState(settings: SettingsStore.inMemory(enabled(false, face: .timetable)))
        XCTAssertEqual(app.face, .utilities)
    }

    func testToggleToTimetableBlockedWhileDisabled() {
        let app = AppState(settings: SettingsStore.inMemory(enabled(false)))
        app.toggleFace(to: .timetable)
        XCTAssertEqual(app.face, .utilities)
    }
}

import XCTest
@testable import NotchDeck

final class TimetableModuleTests: XCTestCase {
    func testDescriptorIsAUtilitiesTabWithoutCapabilities() {
        let d = TimetableModule.descriptor
        XCTAssertEqual(d.identifier, "built-in.timetable")
        XCTAssertTrue(d.surfaces.contains(.expandedTab))
        XCTAssertTrue(d.surfaces.contains(.settingsSection))
        XCTAssertFalse(d.surfaces.contains(.workspace))
        XCTAssertTrue(d.capabilities.isEmpty)
        XCTAssertTrue(d.hasSettings)
        XCTAssertTrue(d.defaultEnabled)
    }

    func testEnablementFollowsTheModuleToggle() {
        XCTAssertTrue(TimetableModule.isEnabled(AppSettings()))
        var settings = AppSettings()
        settings.moduleEnabled[TimetableModule.identifier] = false
        XCTAssertFalse(TimetableModule.isEnabled(settings))
    }

    func testModuleIsNeitherAHomeCardNorAMoreCard() {
        let entry = ModuleCatalogEntry(descriptor: TimetableModule.descriptor, source: .builtIn)
        XCTAssertFalse(entry.isHomeModule)
        XCTAssertFalse(entry.isMoreModule)
    }

    func testTabSitsBeforeMoreOnlyWhileEnabled() {
        XCTAssertEqual(UtilitiesTab.visible(timetableEnabled: true),
                       [.home, .focus, .files, .timetable, .more])
        XCTAssertEqual(UtilitiesTab.visible(timetableEnabled: false), [.home, .focus, .files, .more])
    }

    func testTimetableTabHasItsOwnWidthProfile() {
        XCTAssertEqual(UtilitiesTab.timetable.widthProfile, .timetable)
        XCTAssertEqual(UtilitiesTab.timetable.icon, "calendar")
    }
}

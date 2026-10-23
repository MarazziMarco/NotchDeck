import XCTest
@testable import SharedWidgets

final class SharedWidgetsTests: XCTestCase {
    private struct Counter: Codable, Equatable, Sendable { var count = 0 }
    private var directory: URL!
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testTwoStaleWritersPreserveEachOthersFieldsAndRecoverBackup() throws {
        let a = SharedWidgetFile<SharedNote>(key: "note", directory: directory)
        let b = SharedWidgetFile<SharedNote>(key: "note", directory: directory)
        try a.update(default: SharedNote()) { $0.text = "Nota con accenti: caffè ☕️\nSeconda riga" }
        try b.update(default: SharedNote()) { $0.color = "mint" }
        let value = try XCTUnwrap(a.read())
        XCTAssertEqual(value.color, "mint")
        XCTAssertTrue(value.text.contains("caffè"))
        try Data("broken".utf8).write(to: a.url)
        XCTAssertEqual(try b.read(), value)
        try b.update(default: SharedNote()) { $0.title = "Recuperata" }
        XCTAssertEqual(try a.read()?.title, "Recuperata")
        XCTAssertEqual(try a.read()?.text, value.text)
    }
    func testMigrationsPreserveBothNotesWithoutDuplicatingThem() {
        var note = SharedNote()
        note.migrate(source: "LaunchPad", text: "Prima nota")
        note.migrate(source: "NotchDeck", text: "Seconda nota")
        note.migrate(source: "LaunchPad", text: "Prima nota")
        note.migrate(source: "NotchDeck", text: "Seconda nota")
        XCTAssertTrue(note.text.contains("Prima nota"))
        XCTAssertTrue(note.text.contains("Seconda nota"))
        XCTAssertEqual(note.text.components(separatedBy: "Seconda nota").count, 2)
    }
    func testConcurrentTransactionsDoNotLoseUpdates() throws {
        let file = SharedWidgetFile<Counter>(key: "counter", directory: directory)
        try file.update(default: Counter()) { _ in }
        DispatchQueue.concurrentPerform(iterations: 60) { _ in
            _ = try? file.update(default: Counter()) { $0.count += 1 }
        }
        XCTAssertEqual(try file.read()?.count, 60)
    }
    @MainActor func testIndependentChannelsRefreshAndKeepStateInBothDirections() throws {
        let a = SharedWidgetChannel(key: "note", initial: SharedNote(), directory: directory, observe: false)
        let b = SharedWidgetChannel(key: "note", initial: SharedNote(), directory: directory, observe: false)
        try a.update { $0.text = "Da LaunchPad" }
        b.refresh()
        XCTAssertEqual(b.value.text, "Da LaunchPad")
        try b.update { $0.color = "peach" }
        a.refresh()
        XCTAssertEqual(a.value.color, "peach")
        XCTAssertEqual(a.value.text, "Da LaunchPad")
    }
    @MainActor func testPlanningWorksStandaloneWithoutNotchDeckData() throws {
        let standalone = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        XCTAssertNil(standalone.timetable.value.timetable)
        let imported = try TimetableImporter.csv(TimetableImporter.exampleCSV)
        try standalone.timetable.update { $0.install(imported) }
        let reopened = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        XCTAssertEqual(reopened.timetable.value.followedLessons.count, 6)
        XCTAssertEqual(reopened.timetable.value.timetable?.courses.count, 3)
        XCTAssertEqual(reopened.timetable.value.timetable, imported)
    }
    func testJSONAndCSVExamplesHaveEquivalentLessons() throws {
        let json = try TimetableImporter.json(Data(TimetableImporter.exampleJSON.utf8))
        let csv = try TimetableImporter.csv(TimetableImporter.exampleCSV)
        XCTAssertEqual(json.lessons.count, 6)
        XCTAssertEqual(json.courses.map(\.name), csv.courses.map(\.name))
        XCTAssertEqual(json.lessons.map(\.start), csv.lessons.map(\.start))
        XCTAssertEqual(json.lessons.map(\.day), csv.lessons.map(\.day))
    }
    func testCSVQuotesSemicolonsBOMAndItalianDays() throws {
        let input = "\u{feff}giorno;inizio;fine;titolo;aula\r\nLunedì;8:00;10:00;\"Fisica; laboratorio\";\"Aula \"\"A\"\"\"\r\n"
        let timetable = try TimetableImporter.csv(input)
        XCTAssertEqual(timetable.courses[0].name, "Fisica; laboratorio")
        XCTAssertEqual(timetable.lessons[0].room, "Aula \"A\"")
        XCTAssertEqual(timetable.lessons[0].start, "08:00")
        XCTAssertEqual(timetable.lessons[0].day, "mon")
    }
    func testInvalidCSVAndJSONAreRejectedBeforeReplacingAnything() {
        XCTAssertThrowsError(try TimetableImporter.csv("day,start,end,title\nmon,12:00,11:00,Bad"))
        XCTAssertThrowsError(try TimetableImporter.csv("day,start,end,title\nmon,09:00,11:00,\"Unclosed"))
        XCTAssertThrowsError(try TimetableImporter.json(Data("{\"events\":[{\"day\":\"mon\",\"start\":\"99:00\",\"end\":\"11:00\",\"title\":\"Bad\"}]}".utf8)))
    }
    func testNotchDeckFormatAndStateAreBothAccepted() throws {
        let input = """
        {"format":"notchdeck-timetable","version":1,"title":"Control Engineering",
         "courses":[{"id":"amr","name":"Mobile Robotics","short":"AMR","color":"#7464CC"}],
         "lessons":[{"course":"amr","day":"mon","start":"10:00","end":"12:00"}]}
        """
        let imported = try TimetableImporter.json(Data(input.utf8))
        var shared = SharedTimetable(); shared.install(imported)
        let importedAgain = try TimetableImporter.json(JSONEncoder().encode(shared))
        XCTAssertEqual(importedAgain.lessons, imported.lessons)
        XCTAssertEqual(importedAgain.courses, imported.courses)
    }
    func testOverlappingLessonsGetLanesAndAdjacentOnesShareFullWidth() {
        let lessons = [
            TimetableLessonData(courseID: "a", day: "mon", start: "09:00", end: "11:00"),
            TimetableLessonData(courseID: "b", day: "mon", start: "10:00", end: "12:00"),
            TimetableLessonData(courseID: "c", day: "mon", start: "12:00", end: "13:00"),
        ]
        let lanes = TimetableLayout.lanes(lessons)
        XCTAssertEqual(lanes[lessons[0].id]?.count, 2)
        XCTAssertEqual(lanes[lessons[1].id]?.count, 2)
        XCTAssertNotEqual(lanes[lessons[0].id]?.index, lanes[lessons[1].id]?.index)
        XCTAssertEqual(lanes[lessons[2].id]?.count, 1)
        XCTAssertEqual(TimetableLayout.nextLesson(lessons, day: "mon", minute: 12 * 60)?.id, lessons[0].id)
    }
}

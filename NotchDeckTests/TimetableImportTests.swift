import XCTest
@testable import NotchDeck

final class TimetableImportTests: XCTestCase {
    private func parse(_ json: String) -> Result<Timetable, TimetableImportError> {
        TimetableImport.parse(Data(json.utf8))
    }

    private func messages(_ json: String) -> [String] {
        if case .failure(let error) = parse(json) { return error.messages }
        XCTFail("expected a validation failure")
        return []
    }

    private let valid = """
    {
      "format": "notchdeck-timetable",
      "version": 1,
      "title": "Control Engineering",
      "term": { "start": "2026-09-28", "end": "2027-01-15" },
      "locations": [ { "id": "diag", "name": "DIAG", "address": "Via Ariosto 25, Roma" } ],
      "courses": [
        { "id": "amr", "name": "Autonomous and Mobile Robotics", "professor": "Oriolo", "group": "2° anno", "color": "#20C997" },
        { "id": "ml", "name": "Machine Learning", "short": "ML!" }
      ],
      "lessons": [
        { "course": "amr", "day": "thu", "start": "8:00", "end": "11:00", "room": "B2", "location": "diag" },
        { "course": "ml", "day": "mon", "start": "13:00", "end": "15:00" },
        { "course": "amr", "day": "mon", "start": "10:00", "end": "12:00", "room": "B2", "location": "diag" }
      ]
    }
    """

    func testValidFileProducesASortedTimetable() throws {
        let timetable = try parse(valid).get()
        XCTAssertEqual(timetable.title, "Control Engineering")
        XCTAssertEqual(timetable.term, TimetableTerm(start: "2026-09-28", end: "2027-01-15"))
        XCTAssertEqual(timetable.locations.map(\.id), ["diag"])
        XCTAssertEqual(timetable.courses.map(\.id), ["amr", "ml"])
        XCTAssertEqual(timetable.courses[0].short, "AMR", "derived when missing")
        XCTAssertEqual(timetable.courses[1].short, "ML!", "explicit short is kept")
        XCTAssertEqual(timetable.courses[0].professor, "Oriolo")
        XCTAssertEqual(timetable.courses[0].colorHex, "#20C997")
        XCTAssertEqual(timetable.lessons.map(\.day), [.mon, .mon, .thu])
        XCTAssertEqual(timetable.lessons.map(\.courseID), ["amr", "ml", "amr"])
        XCTAssertEqual(timetable.lessons[2].start, ClockTime(minutes: 8 * 60))
        XCTAssertEqual(timetable.lessons[2].locationID, "diag")
    }

    func testOptionalSectionsMayBeOmitted() throws {
        let timetable = try parse("""
        { "format": "notchdeck-timetable", "version": 1,
          "courses": [ { "id": "a", "name": "Robotics I" } ],
          "lessons": [ { "course": "a", "day": "fri", "start": "08:00", "end": "11:00" } ] }
        """).get()
        XCTAssertNil(timetable.title)
        XCTAssertNil(timetable.term)
        XCTAssertTrue(timetable.locations.isEmpty)
        XCTAssertNil(timetable.lessons[0].room)
    }

    func testWrongFormatAndVersionAreRejected() {
        XCTAssertEqual(messages("""
        { "format": "routine-orario", "version": 1, "courses": [], "lessons": [] }
        """), ["format: expected \"notchdeck-timetable\", found \"routine-orario\""])
        XCTAssertEqual(messages("""
        { "format": "notchdeck-timetable", "version": 2, "courses": [], "lessons": [] }
        """), ["version: unsupported version 2 (expected 1)"])
    }

    func testMalformedJSONGivesOneReadableMessage() {
        let result = messages("{ not json")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].hasPrefix("The file is not valid JSON"), result[0])
    }

    func testMissingRequiredKeyNamesItsPath() {
        let result = messages("""
        { "format": "notchdeck-timetable", "version": 1,
          "courses": [ { "id": "a", "name": "A" } ],
          "lessons": [ { "course": "a", "start": "08:00", "end": "09:00" } ] }
        """)
        XCTAssertEqual(result, ["lessons[0].day: missing"])
    }

    func testEveryLessonAndCourseProblemIsCollected() {
        let result = messages("""
        { "format": "notchdeck-timetable", "version": 1,
          "term": { "start": "2027-01-15", "end": "2026-09-28" },
          "locations": [ { "id": "x", "name": "X" }, { "id": "x", "name": "X again" } ],
          "courses": [
            { "id": "a", "name": "A", "color": "red" },
            { "id": "a", "name": "Duplicate" },
            { "id": "b", "name": " " }
          ],
          "lessons": [
            { "course": "zzz", "day": "mon", "start": "08:00", "end": "09:00" },
            { "course": "a", "day": "monday", "start": "08:00", "end": "09:00" },
            { "course": "a", "day": "tue", "start": "25:00", "end": "09:00" },
            { "course": "a", "day": "wed", "start": "10:00", "end": "09:00" },
            { "course": "a", "day": "thu", "start": "08:00", "end": "09:00", "location": "nowhere" }
          ] }
        """)
        XCTAssertEqual(result, [
            "term: start 2027-01-15 is after end 2026-09-28",
            "locations[1]: duplicate id \"x\"",
            "courses[0]: color \"red\" is not #RRGGBB",
            "courses[1]: duplicate id \"a\"",
            "courses[2]: name is empty",
            "lessons[0]: course \"zzz\" is not defined",
            "lessons[1]: day \"monday\" is not one of mon, tue, wed, thu, fri, sat, sun",
            "lessons[2]: start \"25:00\" is not HH:mm",
            "lessons[3]: start 10:00 is not before end 09:00",
            "lessons[4]: location \"nowhere\" is not defined",
        ])
    }

    func testInvalidTermDateIsRejected() {
        XCTAssertEqual(messages("""
        { "format": "notchdeck-timetable", "version": 1,
          "term": { "start": "2026-02-30", "end": "2026-03-01" },
          "courses": [ { "id": "a", "name": "A" } ], "lessons": [] }
        """), ["term: start \"2026-02-30\" is not a yyyy-MM-dd date"])
    }

    func testAFileWithoutCoursesIsRejected() {
        XCTAssertEqual(messages("""
        { "format": "notchdeck-timetable", "version": 1, "courses": [], "lessons": [] }
        """), ["courses: the file defines no courses"])
    }

    func testAcronymRules() {
        XCTAssertEqual(TimetableCourse.acronym(for: "Autonomous and Mobile Robotics"), "AMR")
        XCTAssertEqual(TimetableCourse.acronym(for: "Control of Communication and Energy Networks"), "CCEN")
        XCTAssertEqual(TimetableCourse.acronym(for: "Robotics I"), "RI")
        XCTAssertEqual(TimetableCourse.acronym(for: "Neuroengineering"), "NEU")
        XCTAssertEqual(TimetableCourse.acronym(for: "Filtering and Optimal Control I"), "FOCI")
        XCTAssertEqual(TimetableCourse.acronym(for: "A Very Long Course Name With Many Words"), "VLCNW")
    }

    func testClockTimeRoundTripsAsText() throws {
        XCTAssertEqual(ClockTime("8:05")?.text, "08:05")
        XCTAssertNil(ClockTime("8"))
        XCTAssertNil(ClockTime("12:60"))
        let data = try JSONEncoder().encode(ClockTime(minutes: 14 * 60 + 30))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"14:30\"")
        XCTAssertEqual(try JSONDecoder().decode(ClockTime.self, from: data), ClockTime(minutes: 870))
    }

    func testWeekdayFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        XCTAssertEqual(Weekday(date: thursday, calendar: calendar), .thu)
        XCTAssertEqual(Weekday(date: sunday, calendar: calendar), .sun)
        XCTAssertEqual(Weekday.mon.isoIndex, 1)
        XCTAssertEqual(Weekday.sun.isoIndex, 7)
    }
}

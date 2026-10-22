import XCTest
@testable import NotchDeck

final class TimetableScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    /// 2026-10-19 is a Monday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func lesson(_ course: String, _ day: Weekday, _ start: String, _ end: String,
                        room: String? = nil) -> TimetableLesson {
        TimetableLesson(courseID: course, day: day, start: ClockTime(start)!, end: ClockTime(end)!, room: room)
    }

    private lazy var timetable = Timetable(
        title: nil, term: nil, locations: [],
        courses: [
            TimetableCourse(id: "amr", name: "AMR", short: "AMR"),
            TimetableCourse(id: "ml", name: "ML", short: "ML"),
        ],
        lessons: [
            lesson("amr", .mon, "10:00", "12:00"),
            lesson("ml", .mon, "14:00", "16:00"),
            lesson("amr", .thu, "08:00", "11:00"),
            lesson("ml", .fri, "09:00", "10:00"),
        ])

    private let both: Set<String> = ["amr", "ml"]

    func testLessonsOnADateRespectFollowedCourses() {
        let monday = at(19, 9)
        XCTAssertEqual(TimetableSchedule.lessons(on: monday, in: timetable, followed: both, calendar: calendar)
            .map(\.courseID), ["amr", "ml"])
        XCTAssertEqual(TimetableSchedule.lessons(on: monday, in: timetable, followed: ["ml"], calendar: calendar)
            .map(\.courseID), ["ml"])
        XCTAssertTrue(TimetableSchedule.lessons(on: at(20, 9), in: timetable, followed: both, calendar: calendar).isEmpty)
    }

    func testNoLessonsOutsideTheTerm() {
        var t = timetable
        t.term = TimetableTerm(start: "2026-10-20", end: "2026-10-23")
        XCTAssertTrue(TimetableSchedule.lessons(on: at(19, 9), in: t, followed: both, calendar: calendar).isEmpty)
        XCTAssertEqual(TimetableSchedule.lessons(on: at(22, 9), in: t, followed: both, calendar: calendar).count, 1)
        XCTAssertEqual(TimetableSchedule.lessons(on: at(23, 9), in: t, followed: both, calendar: calendar).count, 1,
                       "term end is inclusive")
        XCTAssertTrue(TimetableSchedule.lessons(on: at(26, 9), in: t, followed: both, calendar: calendar).isEmpty)
    }

    func testStatusAtExactStartIsCurrent() {
        let status = TimetableSchedule.status(at: at(19, 10), in: timetable, followed: both, calendar: calendar)
        XCTAssertEqual(status.current?.lesson.courseID, "amr")
        XCTAssertEqual(status.current?.end, at(19, 12))
        XCTAssertEqual(status.next?.lesson.courseID, "ml")
        XCTAssertEqual(status.next?.start, at(19, 14))
    }

    func testStatusAtExactEndIsNotCurrent() {
        let status = TimetableSchedule.status(at: at(19, 12), in: timetable, followed: both, calendar: calendar)
        XCTAssertNil(status.current)
        XCTAssertEqual(status.next?.start, at(19, 14))
    }

    func testAfterTheLastLessonNextIsAnotherDay() {
        let status = TimetableSchedule.status(at: at(19, 17), in: timetable, followed: both, calendar: calendar)
        XCTAssertNil(status.current)
        XCTAssertEqual(status.next?.lesson.courseID, "amr")
        XCTAssertEqual(status.next?.start, at(22, 8))
    }

    func testFridayEveningPointsToNextMonday() {
        let status = TimetableSchedule.status(at: at(23, 18), in: timetable, followed: both, calendar: calendar)
        XCTAssertEqual(status.next?.start, at(26, 10))
    }

    func testEmptyFollowedSetHasNoStatus() {
        let status = TimetableSchedule.status(at: at(19, 10), in: timetable, followed: [], calendar: calendar)
        XCTAssertNil(status.current)
        XCTAssertNil(status.next)
    }

    func testNextStopsAtTermEnd() {
        var t = timetable
        t.term = TimetableTerm(start: "2026-09-01", end: "2026-10-23")
        let status = TimetableSchedule.status(at: at(23, 18), in: t, followed: both, calendar: calendar)
        XCTAssertNil(status.next)
    }

    func testUpcomingOccurrencesIncludeTheOngoingLesson() {
        let list = TimetableSchedule.upcomingOccurrences(of: "amr", from: at(19, 11), count: 3,
                                                        in: timetable, calendar: calendar)
        XCTAssertEqual(list.map(\.start), [at(19, 10), at(22, 8), at(26, 10)])
    }

    func testHourRangeSpansFollowedLessons() {
        XCTAssertEqual(TimetableSchedule.hourRange(for: timetable.lessons), 8...16)
        XCTAssertEqual(TimetableSchedule.hourRange(for: [lesson("a", .mon, "09:30", "10:15")]), 9...11)
        XCTAssertEqual(TimetableSchedule.hourRange(for: []), 8...18)
    }

    func testVisibleDaysAddWeekendOnlyWhenUsed() {
        XCTAssertEqual(TimetableSchedule.visibleDays(for: timetable.lessons), [.mon, .tue, .wed, .thu, .fri])
        XCTAssertEqual(TimetableSchedule.visibleDays(for: [lesson("a", .sun, "09:00", "10:00")]),
                       [.mon, .tue, .wed, .thu, .fri, .sun])
    }

    func testPaletteColourIsStableAndExplicitColourWins() {
        let a = TimetableCourse(id: "a", name: "A", short: "A")
        let b = TimetableCourse(id: "b", name: "B", short: "B")
        let ids = ["b", "a"]
        XCTAssertEqual(TimetableSchedule.colorHex(for: a, among: ids), TimetableSchedule.palette[0])
        XCTAssertEqual(TimetableSchedule.colorHex(for: b, among: ids), TimetableSchedule.palette[1])
        var red = a
        red.colorHex = "#FF0000"
        XCTAssertEqual(TimetableSchedule.colorHex(for: red, among: ids), "#FF0000")
    }

    func testMapsURLPrefersAddressThenNameThenRoom() {
        let full = TimetableLocation(id: "d", name: "DIAG", address: "Via Ariosto 25, Roma")
        let bare = TimetableLocation(id: "d", name: "DIAG")
        XCTAssertEqual(TimetableSchedule.mapsURL(room: "B2", location: full)?.absoluteString,
                       "https://maps.apple.com/?q=Via%20Ariosto%2025,%20Roma")
        XCTAssertEqual(TimetableSchedule.mapsURL(room: "B2", location: bare)?.absoluteString,
                       "https://maps.apple.com/?q=DIAG")
        XCTAssertEqual(TimetableSchedule.mapsURL(room: "Room 41 SPV", location: nil)?.absoluteString,
                       "https://maps.apple.com/?q=Room%2041%20SPV")
        XCTAssertNil(TimetableSchedule.mapsURL(room: nil, location: nil))
    }

    func testDayKeysAndCountdowns() {
        XCTAssertEqual(TimetableSchedule.dayKey(at(19, 23, 30), calendar: calendar), "2026-10-19")
        XCTAssertEqual(TimetableSchedule.daysUntil("2026-10-19", from: at(19, 23), calendar: calendar), 0)
        XCTAssertEqual(TimetableSchedule.daysUntil("2026-11-02", from: at(19, 23), calendar: calendar), 14)
        XCTAssertEqual(TimetableSchedule.daysUntil("2026-10-18", from: at(19, 1), calendar: calendar), -1)
        XCTAssertEqual(TimetableSchedule.minutes(from: at(19, 10), to: at(19, 11, 30)), 90)
    }
}

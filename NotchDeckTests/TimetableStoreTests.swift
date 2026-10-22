import XCTest
@testable import NotchDeck

@MainActor
final class TimetableStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timetable-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func makeStore() -> TimetableStore {
        TimetableStore(file: JSONFileStore(url: url))
    }

    private func file(courses: String, lessons: String) -> Data {
        Data("""
        { "format": "notchdeck-timetable", "version": 1,
          "courses": [\(courses)], "lessons": [\(lessons)] }
        """.utf8)
    }

    private let twoCourses = """
    { "id": "amr", "name": "Autonomous and Mobile Robotics" }, { "id": "ml", "name": "Machine Learning" }
    """
    private let twoLessons = """
    { "course": "amr", "day": "mon", "start": "10:00", "end": "12:00" },
    { "course": "ml", "day": "wed", "start": "08:00", "end": "11:00" }
    """

    func testImportPersistsAndReloads() throws {
        let store = makeStore()
        XCTAssertNil(store.timetable)
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        XCTAssertEqual(store.courses.map(\.id), ["amr", "ml"])
        XCTAssertEqual(store.lessons.count, 2)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.timetable, store.timetable)
    }

    func testInvalidImportLeavesTheCurrentTimetable() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        let result = store.importFile(Data("{}".utf8))
        guard case .failure = result else { return XCTFail("expected failure") }
        XCTAssertEqual(store.lessons.count, 2)
    }

    func testCoursesAreFollowedByDefaultWithoutGroups() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        XCTAssertEqual(store.followedIDs, ["amr", "ml"])
    }

    func testGroupedCoursesStartUnfollowed() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: """
        { "id": "amr", "name": "AMR", "group": "2° anno" }, { "id": "ml", "name": "ML", "group": "2° anno" }
        """, lessons: twoLessons)).get()
        XCTAssertEqual(store.followedIDs, [])
        store.setFollowed("ml", true)
        XCTAssertEqual(store.followedIDs, ["ml"])
    }

    func testReimportKeepsUserDataByCourseIDIncludingDormantCourses() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        store.setFollowed("ml", false)
        store.setNote("ml", "Bishop chapter 1–4")
        store.setLessonNote(courseID: "amr", dayKey: "2026-10-26", "bring laptop")

        // ML disappears from the new file: its data stays, dormant.
        _ = try store.importFile(file(courses: """
        { "id": "amr", "name": "Autonomous and Mobile Robotics" }
        """, lessons: """
        { "course": "amr", "day": "tue", "start": "09:00", "end": "10:00" }
        """)).get()
        XCTAssertEqual(store.courses.map(\.id), ["amr"])
        XCTAssertEqual(store.lessonNote(courseID: "amr", dayKey: "2026-10-26"), "bring laptop")

        // ML returns: its note and unfollowed choice come back.
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        XCTAssertEqual(store.note("ml"), "Bishop chapter 1–4")
        XCTAssertFalse(store.isFollowed("ml"))
        XCTAssertEqual(makeStore().note("ml"), "Bishop chapter 1–4", "persisted")
    }

    func testBlankLessonNoteIsRemoved() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        store.setLessonNote(courseID: "amr", dayKey: "2026-10-26", "quiz")
        store.setLessonNote(courseID: "amr", dayKey: "2026-10-26", "  ")
        XCTAssertNil(store.lessonNote(courseID: "amr", dayKey: "2026-10-26"))
        XCTAssertEqual(store.state.userData["amr"]?.lessonNotes, [:])
    }

    func testExamsUpsertDeleteAndSortByDate() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        var exam = TimetableExam(date: "2027-01-20", kind: .exam, note: "")
        store.upsertExam(exam, courseID: "amr")
        store.upsertExam(TimetableExam(date: "2026-12-01", kind: .midterm, note: "ch. 1–3"), courseID: "amr")
        XCTAssertEqual(store.exams(for: "amr").map(\.date), ["2026-12-01", "2027-01-20"])

        exam.note = "oral"
        store.upsertExam(exam, courseID: "amr")
        XCTAssertEqual(store.exams(for: "amr").last?.note, "oral")
        XCTAssertEqual(store.exams(for: "amr").count, 2)

        store.deleteExam(exam.id, courseID: "amr")
        XCTAssertEqual(store.exams(for: "amr").map(\.kind), [.midterm])
    }

    func testLessonCRUDKeepsDisplayOrder() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        let added = TimetableLesson(courseID: "ml", day: .mon, start: ClockTime("08:00")!, end: ClockTime("09:00")!)
        store.addLesson(added)
        XCTAssertEqual(store.lessons.first?.id, added.id, "Monday 08:00 sorts first")

        var moved = added
        moved.day = .fri
        store.updateLesson(moved)
        XCTAssertEqual(store.lessons.last?.id, added.id)

        store.deleteLesson(added.id)
        XCTAssertEqual(store.lessons.count, 2)
        XCTAssertEqual(makeStore().lessons.count, 2, "persisted")
    }

    func testRemoveTimetableKeepsUserData() throws {
        let store = makeStore()
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        store.setNote("amr", "keep me")
        store.removeTimetable()
        XCTAssertNil(store.timetable)
        _ = try store.importFile(file(courses: twoCourses, lessons: twoLessons)).get()
        XCTAssertEqual(store.note("amr"), "keep me")
    }
}

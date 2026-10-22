import Foundation
import Combine

/// Owns the imported timetable and the user's own data (followed courses,
/// notes, exams). Everything is one small local JSON file; each change is
/// written immediately. User data is keyed by course id, so a re-import keeps
/// it — and data for a course missing from the new file stays dormant until the
/// id comes back.
@MainActor
final class TimetableStore: ObservableObject {
    @Published private(set) var state: TimetableState

    private let file: JSONFileStore<TimetableState>

    init(file: JSONFileStore<TimetableState> = JSONFileStore(fileName: "timetable.json")) {
        self.file = file
        self.state = file.load() ?? TimetableState()
    }

    var timetable: Timetable? { state.timetable }
    var courses: [TimetableCourse] { state.timetable?.courses ?? [] }
    var lessons: [TimetableLesson] { state.timetable?.lessons ?? [] }

    /// Ids of the current courses the user follows.
    var followedIDs: Set<String> { Set(courses.map(\.id).filter(isFollowed)) }

    // MARK: Import

    /// Replaces the timetable with a valid file; an invalid file changes nothing.
    @discardableResult
    func importFile(_ data: Data) -> Result<Timetable, TimetableImportError> {
        let result = TimetableImport.parse(data)
        if case .success(let timetable) = result { install(timetable) }
        return result
    }

    /// New courses are followed by default only when the file has no groups —
    /// a grouped file (e.g. 1st/2nd year) lets the user pick theirs.
    private func install(_ timetable: Timetable) {
        let followByDefault = !timetable.courses.contains { $0.group != nil }
        mutate { state in
            for course in timetable.courses where state.userData[course.id] == nil {
                state.userData[course.id] = CourseUserData(followed: followByDefault)
            }
            state.timetable = timetable
        }
    }

    /// Removes the timetable; notes and exams stay for a later import.
    func removeTimetable() {
        mutate { $0.timetable = nil }
    }

    // MARK: Courses

    func isFollowed(_ courseID: String) -> Bool { state.userData[courseID]?.followed ?? false }

    func setFollowed(_ courseID: String, _ followed: Bool) {
        mutateUserData(courseID) { $0.followed = followed }
    }

    func note(_ courseID: String) -> String { state.userData[courseID]?.note ?? "" }

    func setNote(_ courseID: String, _ note: String) {
        mutateUserData(courseID) { $0.note = note }
    }

    func lessonNote(courseID: String, dayKey: String) -> String? {
        state.userData[courseID]?.lessonNotes[dayKey]
    }

    /// A blank note removes the entry.
    func setLessonNote(courseID: String, dayKey: String, _ note: String) {
        let blank = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        mutateUserData(courseID) { $0.lessonNotes[dayKey] = blank ? nil : note }
    }

    // MARK: Exams

    func exams(for courseID: String) -> [TimetableExam] {
        (state.userData[courseID]?.exams ?? []).sorted { $0.date < $1.date }
    }

    func upsertExam(_ exam: TimetableExam, courseID: String) {
        mutateUserData(courseID) { data in
            if let index = data.exams.firstIndex(where: { $0.id == exam.id }) {
                data.exams[index] = exam
            } else {
                data.exams.append(exam)
            }
        }
    }

    func deleteExam(_ id: UUID, courseID: String) {
        mutateUserData(courseID) { $0.exams.removeAll { $0.id == id } }
    }

    // MARK: Lessons

    func addLesson(_ lesson: TimetableLesson) {
        mutateLessons { $0.append(lesson) }
    }

    func updateLesson(_ lesson: TimetableLesson) {
        mutateLessons { lessons in
            guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
            lessons[index] = lesson
        }
    }

    func deleteLesson(_ id: UUID) {
        mutateLessons { $0.removeAll { $0.id == id } }
    }

    // MARK: Mutation

    private func mutateLessons(_ change: (inout [TimetableLesson]) -> Void) {
        guard state.timetable != nil else { return }
        mutate { state in
            change(&state.timetable!.lessons)
            state.timetable!.lessons.sort(by: TimetableLesson.displayOrder)
        }
    }

    private func mutateUserData(_ courseID: String, _ change: (inout CourseUserData) -> Void) {
        mutate { state in
            var data = state.userData[courseID] ?? CourseUserData(followed: false)
            change(&data)
            state.userData[courseID] = data
        }
    }

    private func mutate(_ change: (inout TimetableState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        file.save(next)
    }
}

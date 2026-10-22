import Foundation

/// Pure timetable logic: which lessons fall on a date, what is on now / next,
/// grid geometry and small formatting helpers. Every function takes the
/// `Calendar` and `Date` explicitly so it is deterministic under test.
enum TimetableSchedule {
    /// One lesson placed on a concrete day.
    struct Occurrence: Equatable {
        let lesson: TimetableLesson
        let start: Date
        let end: Date
    }

    struct NowStatus: Equatable {
        var current: Occurrence?
        var next: Occurrence?
    }

    /// Stable course colours (used when the file gives none).
    static let palette = ["#8577FF", "#20C997", "#FF7A3D", "#F0588C", "#3BC9DB", "#FCC419", "#94D82D", "#E599F7"]

    /// How far ahead `status` looks for the next lesson.
    private static let nextLessonHorizonDays = 14
    /// How far ahead `upcomingOccurrences` looks.
    private static let upcomingHorizonDays = 366

    // MARK: Days

    /// `yyyy-MM-dd` for `date` in `calendar`'s time zone.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of the day named by a `yyyy-MM-dd` key.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole days from today to `key` (negative when in the past).
    static func daysUntil(_ key: String, from now: Date, calendar: Calendar) -> Int? {
        guard let target = date(fromDayKey: key, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: target).day
    }

    /// Minutes from `start` to `end`, rounded up (so "ends in 1 min" until it ends).
    static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded(.up))
    }

    static func isInTerm(_ date: Date, term: TimetableTerm?, calendar: Calendar) -> Bool {
        guard let term else { return true }
        let key = dayKey(date, calendar: calendar)
        return key >= term.start && key <= term.end
    }

    // MARK: Lessons

    /// Followed lessons on `date`'s weekday, by start time; none outside the term.
    static func lessons(on date: Date, in timetable: Timetable, followed: Set<String>,
                        calendar: Calendar) -> [TimetableLesson] {
        guard isInTerm(date, term: timetable.term, calendar: calendar) else { return [] }
        let day = Weekday(date: date, calendar: calendar)
        return timetable.lessons
            .filter { $0.day == day && followed.contains($0.courseID) }
            .sorted(by: TimetableLesson.displayOrder)
    }

    static func occurrence(of lesson: TimetableLesson, on date: Date, calendar: Calendar) -> Occurrence {
        let day = calendar.startOfDay(for: date)
        func time(_ t: ClockTime) -> Date {
            calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) ?? day
        }
        return Occurrence(lesson: lesson, start: time(lesson.start), end: time(lesson.end))
    }

    /// The lesson in progress (start inclusive, end exclusive) and the next one
    /// to start, looking up to two weeks ahead.
    static func status(at now: Date, in timetable: Timetable, followed: Set<String>,
                       calendar: Calendar) -> NowStatus {
        let today = lessons(on: now, in: timetable, followed: followed, calendar: calendar)
            .map { occurrence(of: $0, on: now, calendar: calendar) }
        var status = NowStatus()
        status.current = today.first { $0.start <= now && now < $0.end }
        status.next = today.first { $0.start > now }
        guard status.next == nil else { return status }
        for offset in 1...nextLessonHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { break }
            if let first = lessons(on: day, in: timetable, followed: followed, calendar: calendar).first {
                status.next = occurrence(of: first, on: day, calendar: calendar)
                break
            }
        }
        return status
    }

    /// The next `count` lessons of one course that have not ended yet (the one
    /// in progress included), regardless of whether the course is followed.
    static func upcomingOccurrences(of courseID: String, from now: Date, count: Int,
                                    in timetable: Timetable, calendar: Calendar) -> [Occurrence] {
        var out: [Occurrence] = []
        for offset in 0..<upcomingHorizonDays where out.count < count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { break }
            if let term = timetable.term, dayKey(day, calendar: calendar) > term.end { break }
            let found = lessons(on: day, in: timetable, followed: [courseID], calendar: calendar)
                .map { occurrence(of: $0, on: day, calendar: calendar) }
                .filter { $0.end > now }
            out.append(contentsOf: found.prefix(count - out.count))
        }
        return out
    }

    // MARK: Grid

    /// Whole hours spanning the earliest start to the latest end (8…18 when empty).
    static func hourRange(for lessons: [TimetableLesson]) -> ClosedRange<Int> {
        guard let first = lessons.map(\.start.minutes).min(),
              let last = lessons.map(\.end.minutes).max() else { return 8...18 }
        let lower = first / 60
        let upper = max(lower + 1, Int((Double(last) / 60).rounded(.up)))
        return lower...upper
    }

    /// Monday–Friday, plus Saturday/Sunday only when a lesson uses them.
    static func visibleDays(for lessons: [TimetableLesson]) -> [Weekday] {
        let used = Set(lessons.map(\.day))
        return Weekday.allCases.filter { $0 < .sat || used.contains($0) }
    }

    /// The file's colour, else a palette colour by the course's sorted position.
    static func colorHex(for course: TimetableCourse, among ids: [String]) -> String {
        if let hex = course.colorHex { return hex }
        let index = ids.sorted().firstIndex(of: course.id) ?? 0
        return palette[index % palette.count]
    }

    /// Apple Maps search for the location's address, else its name, else the room.
    static func mapsURL(room: String?, location: TimetableLocation?) -> URL? {
        guard let query = location?.address ?? location?.name ?? room else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

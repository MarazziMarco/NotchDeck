import Foundation

public struct TimetableCourseData: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var short: String
    public var professor: String?
    public var group: String?
    public var colorHex: String?
    public init(id: String, name: String, short: String? = nil, color: String? = nil) {
        self.id = id; self.name = name
        self.short = short ?? String(name.split(separator: " ").compactMap(\.first).prefix(5)).uppercased()
        if self.short.count < 2 { self.short = String(name.prefix(4)).uppercased() }
        colorHex = color
    }
}

public struct TimetableLocationData: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: String?
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct TimetableLessonData: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var courseID: String
    /// Monday = mon ... Sunday = sun, matching NotchDeck's exported format.
    public var day: String
    public var start: String
    public var end: String
    public var room: String?
    public var locationID: String?
    public init(id: UUID = UUID(), courseID: String, day: String, start: String, end: String,
                room: String? = nil, locationID: String? = nil) {
        self.id = id; self.courseID = courseID; self.day = day; self.start = start; self.end = end
        self.room = room; self.locationID = locationID
    }
    public var startMinute: Int { TimetableClock.minutes(start) ?? 0 }
    public var endMinute: Int { TimetableClock.minutes(end) ?? 0 }
}

public struct TimetableTermData: Codable, Equatable, Sendable {
    public var start: String
    public var end: String
}

public struct WeeklyTimetable: Codable, Equatable, Sendable {
    public var title: String?
    public var term: TimetableTermData?
    public var locations: [TimetableLocationData] = []
    public var courses: [TimetableCourseData] = []
    public var lessons: [TimetableLessonData] = []
    public init(title: String? = nil, courses: [TimetableCourseData] = [], lessons: [TimetableLessonData] = []) {
        self.title = title; self.courses = courses; self.lessons = lessons
    }
}

public struct TimetableExamData: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: String
    public var kind: String
    public var note: String
}

public struct TimetableCourseState: Codable, Equatable, Sendable {
    public var followed: Bool
    public var note = ""
    public var lessonNotes: [String: String] = [:]
    public var exams: [TimetableExamData] = []
    public init(followed: Bool) { self.followed = followed }
}

public struct TimetablePDF: Codable, Equatable, Sendable {
    public var name: String
    public var data: Data
    public init(name: String, data: Data) { self.name = name; self.data = data }
}

/// The structured portion matches NotchDeck's existing state byte-for-byte in JSON shape.
public struct SharedTimetable: Codable, Equatable, Sendable {
    public var routineLinked: Bool?
    public var timetable: WeeklyTimetable?
    public var userData: [String: TimetableCourseState] = [:]
    public var pdf: TimetablePDF?
    public var migratedSources: Set<String>?
    public init() {}
    public var followedLessons: [TimetableLessonData] {
        (timetable?.lessons ?? []).filter { userData[$0.courseID]?.followed ?? true }
    }
    public mutating func install(_ timetable: WeeklyTimetable) {
        for course in timetable.courses where userData[course.id] == nil {
            userData[course.id] = TimetableCourseState(followed: course.group == nil)
        }
        self.timetable = timetable
        pdf = nil
    }
}

public enum TimetableClock {
    public static let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    public static func day(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT")).lowercased()
        let aliases = [
            ["mon", "monday", "lun", "lunedi", "1"], ["tue", "tuesday", "mar", "martedi", "2"],
            ["wed", "wednesday", "mer", "mercoledi", "3"], ["thu", "thursday", "gio", "giovedi", "4"],
            ["fri", "friday", "ven", "venerdi", "5"], ["sat", "saturday", "sab", "sabato", "6"],
            ["sun", "sunday", "dom", "domenica", "7"],
        ]
        return aliases.firstIndex(where: { $0.contains(text) }).map { days[$0] }
    }
    public static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
    public static func text(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    public static func today(_ date: Date = .now, calendar: Calendar = .current) -> String {
        days[(calendar.component(.weekday, from: date) + 5) % 7]
    }
}

public struct TimetableLane: Equatable, Sendable {
    public var index: Int
    public var count: Int
}

public enum TimetableLayout {
    public static func nextLesson(_ lessons: [TimetableLessonData], day: String, minute: Int) -> TimetableLessonData? {
        let today = TimetableClock.days.firstIndex(of: day) ?? 0
        func distance(_ lesson: TimetableLessonData) -> (Int, Int) {
            var days = ((TimetableClock.days.firstIndex(of: lesson.day) ?? 0) - today + 7) % 7
            if days == 0 && lesson.startMinute <= minute { days = 7 }
            return (days, lesson.startMinute)
        }
        return lessons.min { distance($0) < distance($1) }
    }
    public static func visibleDays(_ lessons: [TimetableLessonData]) -> [String] {
        TimetableClock.days.filter { day in
            !["sat", "sun"].contains(day) || lessons.contains(where: { $0.day == day })
        }
    }
    public static func lanes(_ lessons: [TimetableLessonData]) -> [UUID: TimetableLane] {
        var result: [UUID: TimetableLane] = [:]
        for day in TimetableClock.days {
            let sorted = lessons.filter { $0.day == day }.sorted {
                ($0.startMinute, $0.endMinute, $0.id.uuidString) < ($1.startMinute, $1.endMinute, $1.id.uuidString)
            }
            var members: [(UUID, Int)] = []
            var ends: [Int] = []
            var clusterEnd = 0
            func finish() {
                for (id, lane) in members { result[id] = TimetableLane(index: lane, count: ends.count) }
                members = []; ends = []; clusterEnd = 0
            }
            for lesson in sorted {
                if lesson.startMinute >= clusterEnd { finish() }
                let lane = ends.firstIndex { $0 <= lesson.startMinute } ?? ends.count
                if lane == ends.count { ends.append(lesson.endMinute) } else { ends[lane] = lesson.endMinute }
                members.append((lesson.id, lane)); clusterEnd = max(clusterEnd, lesson.endMinute)
            }
            finish()
        }
        return result
    }
}

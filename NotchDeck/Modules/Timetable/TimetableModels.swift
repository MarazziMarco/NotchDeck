import Foundation

/// Day of the week as written in a timetable file (`mon` … `sun`).
enum Weekday: String, Codable, CaseIterable, Comparable {
    case mon, tue, wed, thu, fri, sat, sun

    /// ISO index: Monday = 1 … Sunday = 7.
    var isoIndex: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// The weekday of `date` in `calendar`'s time zone.
    init(date: Date, calendar: Calendar) {
        // Calendar weekday: Sunday = 1 … Saturday = 7.
        let weekday = calendar.component(.weekday, from: date)
        self = Self.allCases[(weekday + 5) % 7]
    }

    var shortLabel: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.isoIndex < rhs.isoIndex }
}

/// A wall-clock time of day, stored as minutes since midnight and written as
/// "HH:mm".
struct ClockTime: Codable, Comparable, Hashable {
    let minutes: Int

    init(minutes: Int) { self.minutes = minutes }

    /// Parses "H:mm" or "HH:mm" (00:00 … 23:59).
    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.minutes = hour * 60 + minute
    }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }
    var text: String { String(format: "%02d:%02d", hour, minute) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = ClockTime(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(raw)\" is not HH:mm")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutes < rhs.minutes }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - Validated timetable (what the app stores and renders)

/// Inclusive semester bounds as `yyyy-MM-dd` day keys (compared as strings).
struct TimetableTerm: Codable, Equatable {
    var start: String
    var end: String
}

struct TimetableLocation: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var address: String?
}

struct TimetableCourse: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// Short label for grid blocks ("AMR").
    var short: String
    var professor: String?
    var group: String?
    /// "#RRGGBB" from the file; nil means a stable palette colour.
    var colorHex: String?

    /// Initials of the meaningful words: words longer than three letters, roman
    /// numerals and all-caps words. A single meaningful word yields its first
    /// three letters. At most five characters.
    static func acronym(for name: String) -> String {
        let romanNumerals: Set<String> = ["I", "II", "III", "IV", "V", "VI"]
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let meaningful = words.filter { word in
            word.count > 3 || romanNumerals.contains(word)
                || (word.count >= 2 && word == word.uppercased())
        }
        if meaningful.count == 1, meaningful[0].count > 3 {
            return String(meaningful[0].prefix(3)).uppercased()
        }
        if meaningful.isEmpty { return String(name.prefix(3)).uppercased() }
        return String(meaningful.compactMap(\.first).prefix(5)).uppercased()
    }
}

struct TimetableLesson: Codable, Equatable, Identifiable {
    var id: UUID
    var courseID: String
    var day: Weekday
    var start: ClockTime
    var end: ClockTime
    var room: String?
    var locationID: String?

    init(id: UUID = UUID(), courseID: String, day: Weekday, start: ClockTime, end: ClockTime,
         room: String? = nil, locationID: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.day = day
        self.start = start
        self.end = end
        self.room = room
        self.locationID = locationID
    }

    /// Display order: day, then start time, then course.
    static func displayOrder(_ lhs: TimetableLesson, _ rhs: TimetableLesson) -> Bool {
        (lhs.day.isoIndex, lhs.start.minutes, lhs.courseID) < (rhs.day.isoIndex, rhs.start.minutes, rhs.courseID)
    }
}

struct Timetable: Codable, Equatable {
    var title: String?
    var term: TimetableTerm?
    var locations: [TimetableLocation]
    var courses: [TimetableCourse]
    var lessons: [TimetableLesson]

    func course(id: String) -> TimetableCourse? { courses.first { $0.id == id } }
    func location(id: String?) -> TimetableLocation? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }
}

// MARK: - User data (kept across re-imports, keyed by course id)

enum TimetableExamKind: String, Codable, CaseIterable, Identifiable {
    case exam, midterm, deadline
    var id: String { rawValue }
    var label: String {
        switch self {
        case .exam: return "Exam"
        case .midterm: return "Midterm"
        case .deadline: return "Deadline"
        }
    }
}

struct TimetableExam: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// `yyyy-MM-dd` day key.
    var date: String
    var kind: TimetableExamKind
    var note: String
}

struct CourseUserData: Codable, Equatable {
    var followed: Bool
    /// The course's fixed note.
    var note: String = ""
    /// Notes for single lessons, keyed by the lesson's `yyyy-MM-dd` day key.
    var lessonNotes: [String: String] = [:]
    var exams: [TimetableExam] = []
}

/// Everything the Timetable module persists.
struct TimetableState: Codable, Equatable {
    var timetable: Timetable?
    var userData: [String: CourseUserData] = [:]
}

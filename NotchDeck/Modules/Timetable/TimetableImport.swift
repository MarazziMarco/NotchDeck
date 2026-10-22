import Foundation

/// The `notchdeck-timetable` file exactly as written on disk. Days and times are
/// plain strings here so validation can report them by path instead of failing
/// the whole decode.
struct TimetableFile: Decodable {
    struct Term: Decodable { var start: String; var end: String }
    struct Location: Decodable { var id: String; var name: String; var address: String? }
    struct Course: Decodable {
        var id: String
        var name: String
        var short: String?
        var professor: String?
        var group: String?
        var color: String?
    }
    struct Lesson: Decodable {
        var course: String
        var day: String
        var start: String
        var end: String
        var room: String?
        var location: String?
    }

    var format: String
    var version: Int
    var title: String?
    var term: Term?
    var locations: [Location]?
    var courses: [Course]
    var lessons: [Lesson]
}

/// All problems found in a file, as readable one-line messages.
struct TimetableImportError: Error, Equatable {
    let messages: [String]
}

/// Decodes and validates a timetable file. All-or-nothing: any problem rejects
/// the file and every problem is reported. Pure.
enum TimetableImport {
    static let format = "notchdeck-timetable"
    static let supportedVersion = 1

    static func parse(_ data: Data) -> Result<Timetable, TimetableImportError> {
        let file: TimetableFile
        do {
            file = try JSONDecoder().decode(TimetableFile.self, from: data)
        } catch {
            return .failure(TimetableImportError(messages: [describe(error)]))
        }
        guard file.format == format else {
            return .failure(TimetableImportError(messages: ["format: expected \"\(format)\", found \"\(file.format)\""]))
        }
        guard file.version == supportedVersion else {
            return .failure(TimetableImportError(messages: ["version: unsupported version \(file.version) (expected \(supportedVersion))"]))
        }

        var errors: [String] = []
        let term = validateTerm(file.term, errors: &errors)
        let locations = validateLocations(file.locations ?? [], errors: &errors)
        let courses = validateCourses(file.courses, errors: &errors)
        let lessons = validateLessons(file.lessons,
                                      courseIDs: Set(file.courses.map { $0.id.trimmed }),
                                      locationIDs: Set(locations.map(\.id)),
                                      errors: &errors)
        guard errors.isEmpty else { return .failure(TimetableImportError(messages: errors)) }
        return .success(Timetable(title: file.title.cleaned, term: term, locations: locations,
                                  courses: courses, lessons: lessons.sorted(by: TimetableLesson.displayOrder)))
    }

    // MARK: Sections

    private static func validateTerm(_ term: TimetableFile.Term?, errors: inout [String]) -> TimetableTerm? {
        guard let term else { return nil }
        var valid = true
        for (label, value) in [("start", term.start), ("end", term.end)] where !isDayKey(value) {
            errors.append("term: \(label) \"\(value)\" is not a yyyy-MM-dd date")
            valid = false
        }
        guard valid else { return nil }
        if term.start > term.end {
            errors.append("term: start \(term.start) is after end \(term.end)")
            return nil
        }
        return TimetableTerm(start: term.start, end: term.end)
    }

    private static func validateLocations(_ entries: [TimetableFile.Location], errors: inout [String]) -> [TimetableLocation] {
        var seen = Set<String>()
        var out: [TimetableLocation] = []
        for (i, entry) in entries.enumerated() {
            let id = entry.id.trimmed
            if id.isEmpty { errors.append("locations[\(i)]: id is empty"); continue }
            if !seen.insert(id).inserted { errors.append("locations[\(i)]: duplicate id \"\(id)\""); continue }
            if entry.name.trimmed.isEmpty { errors.append("locations[\(i)]: name is empty"); continue }
            out.append(TimetableLocation(id: id, name: entry.name.trimmed, address: entry.address.cleaned))
        }
        return out
    }

    private static func validateCourses(_ entries: [TimetableFile.Course], errors: inout [String]) -> [TimetableCourse] {
        if entries.isEmpty { errors.append("courses: the file defines no courses") }
        var seen = Set<String>()
        var out: [TimetableCourse] = []
        for (i, entry) in entries.enumerated() {
            let id = entry.id.trimmed
            let name = entry.name.trimmed
            if id.isEmpty { errors.append("courses[\(i)]: id is empty"); continue }
            if !seen.insert(id).inserted { errors.append("courses[\(i)]: duplicate id \"\(id)\""); continue }
            if name.isEmpty { errors.append("courses[\(i)]: name is empty"); continue }
            if let color = entry.color, !isHexColor(color) {
                errors.append("courses[\(i)]: color \"\(color)\" is not #RRGGBB")
                continue
            }
            out.append(TimetableCourse(
                id: id, name: name,
                short: entry.short.cleaned ?? TimetableCourse.acronym(for: name),
                professor: entry.professor.cleaned, group: entry.group.cleaned,
                colorHex: entry.color?.uppercased()))
        }
        return out
    }

    private static func validateLessons(_ entries: [TimetableFile.Lesson], courseIDs: Set<String>,
                                        locationIDs: Set<String>, errors: inout [String]) -> [TimetableLesson] {
        var out: [TimetableLesson] = []
        for (i, entry) in entries.enumerated() {
            let prefix = "lessons[\(i)]"
            let courseID = entry.course.trimmed
            var valid = true
            if !courseIDs.contains(courseID) {
                errors.append("\(prefix): course \"\(courseID)\" is not defined"); valid = false
            }
            let day = Weekday(rawValue: entry.day.trimmed.lowercased())
            if day == nil {
                let allowed = Weekday.allCases.map(\.rawValue).joined(separator: ", ")
                errors.append("\(prefix): day \"\(entry.day)\" is not one of \(allowed)"); valid = false
            }
            let start = ClockTime(entry.start)
            let end = ClockTime(entry.end)
            if start == nil { errors.append("\(prefix): start \"\(entry.start)\" is not HH:mm"); valid = false }
            if end == nil { errors.append("\(prefix): end \"\(entry.end)\" is not HH:mm"); valid = false }
            if let start, let end, start >= end {
                errors.append("\(prefix): start \(start.text) is not before end \(end.text)"); valid = false
            }
            let locationID = entry.location.cleaned
            if let locationID, !locationIDs.contains(locationID) {
                errors.append("\(prefix): location \"\(locationID)\" is not defined"); valid = false
            }
            guard valid, let day, let start, let end else { continue }
            out.append(TimetableLesson(courseID: courseID, day: day, start: start, end: end,
                                       room: entry.room.cleaned, locationID: locationID))
        }
        return out
    }

    // MARK: Helpers

    /// True for a real calendar date written as `yyyy-MM-dd`.
    static func isDayKey(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.count == 10, parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }

    private static func isHexColor(_ text: String) -> Bool {
        text.count == 7 && text.first == "#" && text.dropFirst().allSatisfy(\.isHexDigit)
    }

    /// One readable line for a decoding failure, naming the JSON path.
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "The file could not be read." }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])): missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)): wrong type"
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty { return "The file is not valid JSON." }
            return "\(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "The file could not be read."
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Optional where Wrapped == String {
    /// Trimmed, with empty strings treated as absent.
    var cleaned: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

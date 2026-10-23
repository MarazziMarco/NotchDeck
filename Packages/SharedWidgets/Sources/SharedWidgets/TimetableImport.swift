import Foundation

public struct TimetableImportError: LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public enum TimetableImporter {
    public static func json(_ data: Data) throws -> WeeklyTimetable {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw TimetableImportError("Il file non è un JSON valido.") }
        if let rows = object as? [[String: Any]] { return try make(title: nil, courses: [], locations: [], rows: rows) }
        guard let outer = object as? [String: Any] else { throw TimetableImportError("Il JSON deve contenere un oggetto o un elenco di lezioni.") }
        let root = (outer["timetable"] as? [String: Any]) ?? outer
        if let format = root["format"] as? String,
           !["notchdeck-timetable", "launchpad-timetable", "marazzi-timetable"].contains(format) {
            throw TimetableImportError("Formato JSON non riconosciuto: \(format).")
        }
        if let version = root["version"] as? Int, version != 1 { throw TimetableImportError("Versione dell’orario non supportata: \(version).") }
        guard let rows = (root["lessons"] ?? root["events"]) as? [[String: Any]] else {
            throw TimetableImportError("Manca l’elenco lessons o events.")
        }
        var timetable = try make(title: root["title"] as? String,
                                 courses: root["courses"] as? [[String: Any]] ?? [],
                                 locations: root["locations"] as? [[String: Any]] ?? [], rows: rows)
        if let term = root["term"] as? [String: String] {
            guard let start = term["start"], let end = term["end"], validDate(start), validDate(end), start <= end else {
                throw TimetableImportError("Le date del semestre devono essere valide, in formato AAAA-MM-GG, con inizio prima della fine.")
            }
            timetable.term = TimetableTermData(start: start, end: end)
        }
        return timetable
    }

    public static func csv(_ text: String, title: String? = nil) throws -> WeeklyTimetable {
        let records = try csvRecords(text)
        guard let first = records.first else { throw TimetableImportError("Il CSV è vuoto.") }
        let aliases: [String: String] = [
            "giorno":"day", "weekday":"day", "day":"day", "inizio":"start", "start":"start", "starttime":"start",
            "fine":"end", "end":"end", "endtime":"end", "titolo":"title", "title":"title", "name":"title", "corso":"title", "materia":"title", "course":"title",
            "sigla":"short", "short":"short", "code":"short", "colore":"color", "color":"color",
            "aula":"room", "room":"room", "sede":"location", "location":"location",
        ]
        let headers = first.map { aliases[normalized($0).replacingOccurrences(of: " ", with: "")] ?? normalized($0) }
        for key in ["day", "start", "end", "title"] where !headers.contains(key) {
            throw TimetableImportError("Il CSV richiede le colonne giorno, inizio, fine, titolo (oppure day, start, end, title). Manca: \(key).")
        }
        guard Set(headers).count == headers.count else { throw TimetableImportError("Il CSV contiene intestazioni duplicate.") }
        let rows = try records.dropFirst().enumerated().map { index, values -> [String: Any] in
            guard values.count == headers.count else { throw TimetableImportError("Riga \(index + 2): numero di colonne diverso dall’intestazione.") }
            return Dictionary(uniqueKeysWithValues: zip(headers, values)).mapValues { $0 as Any }
        }
        return try make(title: title, courses: [], locations: [], rows: rows)
    }

    public static func csvRecords(_ text: String) throws -> [[String]] {
        let source = text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let firstLine = source.prefix(while: { $0 != "\n" })
        let separator: Character = [Character(","), ";", "\t"].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
        let chars = Array(source)
        var records: [[String]] = []; var row: [String] = []; var field = ""; var quoted = false; var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if quoted, i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if quoted { quoted = false }
                else if field.trimmingCharacters(in: .whitespaces).isEmpty { field = ""; quoted = true }
                else { throw TimetableImportError("Virgolette non valide nel CSV.") }
            } else if char == separator && !quoted {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if char == "\n" && !quoted {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
                if row.contains(where: { !$0.isEmpty }) { records.append(row) }
                row = []
            } else { field.append(char) }
            i += 1
        }
        guard !quoted else { throw TimetableImportError("Una cella del CSV contiene virgolette non chiuse.") }
        row.append(field.trimmingCharacters(in: .whitespaces))
        if row.contains(where: { !$0.isEmpty }) { records.append(row) }
        return records
    }

    private static func make(title: String?, courses rawCourses: [[String: Any]], locations rawLocations: [[String: Any]], rows: [[String: Any]]) throws -> WeeklyTimetable {
        guard !rows.isEmpty else { throw TimetableImportError("L’orario non contiene lezioni.") }
        guard rows.count <= 2000 else { throw TimetableImportError("Il file contiene troppe lezioni (massimo 2000).") }
        var courses: [TimetableCourseData] = []
        var locations: [TimetableLocationData] = []
        for raw in rawCourses {
            guard let id = string(raw, "id"), let name = string(raw, "name"), !courses.contains(where: { $0.id == id }) else {
                throw TimetableImportError("Ogni corso deve avere un id unico e un nome.")
            }
            let color = string(raw, "color") ?? string(raw, "colorHex")
            try validateColor(color)
            var course = TimetableCourseData(id: id, name: name, short: string(raw, "short"), color: color)
            course.professor = string(raw, "professor"); course.group = string(raw, "group")
            courses.append(course)
        }
        for raw in rawLocations {
            guard let id = string(raw, "id"), let name = string(raw, "name"), !locations.contains(where: { $0.id == id }) else {
                throw TimetableImportError("Ogni sede deve avere un id unico e un nome.")
            }
            var location = TimetableLocationData(id: id, name: name); location.address = string(raw, "address")
            locations.append(location)
        }
        var lessons: [TimetableLessonData] = []
        var ids = Set<UUID>()
        for (index, raw) in rows.enumerated() {
            let prefix = "Lezione \(index + 1): "
            guard let rawDay = string(raw, "day"), let day = TimetableClock.day(rawDay) else { throw TimetableImportError(prefix + "giorno non valido.") }
            guard let start = string(raw, "start").flatMap(TimetableClock.minutes), start < 1440,
                  let end = string(raw, "end").flatMap(TimetableClock.minutes), start < end else {
                throw TimetableImportError(prefix + "orari non validi: usa HH:mm, con fine dopo l’inizio.")
            }
            let courseID: String
            if let reference = string(raw, "course") ?? string(raw, "courseID"), !rawCourses.isEmpty {
                guard courses.contains(where: { $0.id == reference }) else { throw TimetableImportError(prefix + "il corso \(reference) non è definito.") }
                courseID = reference
            } else {
                guard let name = string(raw, "title") ?? string(raw, "name") ?? string(raw, "course") else {
                    throw TimetableImportError(prefix + "manca il titolo del corso.")
                }
                courseID = normalized(name)
                if !courses.contains(where: { $0.id == courseID }) {
                    let color = string(raw, "color"); try validateColor(color)
                    courses.append(TimetableCourseData(id: courseID, name: name, short: string(raw, "short"), color: color))
                }
            }
            var locationID = string(raw, "locationID") ?? string(raw, "location")
            if let location = locationID, !locations.contains(where: { $0.id == location }) {
                if !rawLocations.isEmpty { throw TimetableImportError(prefix + "sede sconosciuta: \(location).") }
                locationID = normalized(location)
                if !locations.contains(where: { $0.id == locationID }) {
                    locations.append(TimetableLocationData(id: locationID!, name: location))
                }
            }
            let id = string(raw, "id").flatMap(UUID.init(uuidString:)) ?? UUID()
            guard ids.insert(id).inserted else { throw TimetableImportError(prefix + "identificativo duplicato.") }
            lessons.append(TimetableLessonData(id: id, courseID: courseID, day: day,
                                               start: TimetableClock.text(start), end: TimetableClock.text(end),
                                               room: string(raw, "room"), locationID: locationID))
        }
        lessons.sort { (TimetableClock.days.firstIndex(of: $0.day) ?? 0, $0.startMinute) < (TimetableClock.days.firstIndex(of: $1.day) ?? 0, $1.startMinute) }
        var output = WeeklyTimetable(title: title, courses: courses, lessons: lessons)
        output.locations = locations
        return output
    }

    private static func string(_ dictionary: [String: Any], _ key: String) -> String? {
        guard let value = dictionary[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func validateColor(_ color: String?) throws {
        if let color, !(color.count == 7 && color.first == "#" && color.dropFirst().allSatisfy(\.isHexDigit)) {
            throw TimetableImportError("Il colore \(color) deve essere nel formato #RRGGBB.")
        }
    }
    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return value.count == 10 && formatter.date(from: value).map { formatter.string(from: $0) == value } == true
    }

    public static let exampleJSON = """
    {
      "title": "Il mio orario",
      "events": [
        {"day":"mon","start":"09:00","end":"11:00","title":"Analisi matematica","short":"AM","color":"#7060CA","room":"A1"},
        {"day":"mon","start":"10:00","end":"12:00","title":"Fisica","short":"FIS","color":"#3189AF","room":"B2"},
        {"day":"tue","start":"14:00","end":"16:00","title":"Laboratorio","short":"LAB","color":"#188774"},
        {"day":"wed","start":"09:00","end":"11:00","title":"Analisi matematica","short":"AM"},
        {"day":"thu","start":"10:00","end":"12:00","title":"Fisica","short":"FIS"},
        {"day":"fri","start":"12:00","end":"14:00","title":"Laboratorio","short":"LAB"}
      ]
    }
    """
    public static let exampleCSV = """
    giorno,inizio,fine,titolo,sigla,colore,aula,sede
    lunedì,09:00,11:00,Analisi matematica,AM,#7060CA,A1,Sede centrale
    lunedì,10:00,12:00,Fisica,FIS,#3189AF,B2,Sede centrale
    martedì,14:00,16:00,Laboratorio,LAB,#188774,,
    mercoledì,09:00,11:00,Analisi matematica,AM,#7060CA,A1,Sede centrale
    giovedì,10:00,12:00,Fisica,FIS,#3189AF,B2,Sede centrale
    venerdì,12:00,14:00,Laboratorio,LAB,#188774,,
    """
}

import Foundation

public struct SharedCountdown: Codable, Equatable, Sendable {
    public var title = "Il prossimo traguardo"
    public var target = Date().addingTimeInterval(7 * 86400)
    public var showSeconds = true
    public var color = "#B09CFF"
    public var symbol = "flag.checkered"
    public init() {}
    public func remaining(at now: Date) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let total = max(0, Int(ceil(target.timeIntervalSince(now))))
        return (total / 86400, total / 3600 % 24, total / 60 % 60, total % 60)
    }
}

public struct HabitDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var target: Int
    /// ISO weekdays, Monday = 1.
    public var weekdays: [Int]
    public var color: String
    public init(id: UUID = UUID(), title: String = "Nuova abitudine", symbol: String = "checkmark", target: Int = 1,
                weekdays: [Int] = Array(1...7), color: String = "#70D4AD") {
        self.id = id; self.title = title; self.symbol = symbol; self.target = target
        self.weekdays = weekdays; self.color = color
    }
}
public struct HabitRecord: Codable, Equatable, Sendable, Identifiable {
    public var definition: HabitDefinition
    public var days: [String: Int] = [:]
    public var id: UUID { definition.id }
    public init(definition: HabitDefinition) { self.definition = definition }
    public func count(on date: Date, calendar: Calendar = .current) -> Int { days[SharedHabits.dayKey(date, calendar: calendar)] ?? 0 }
    public func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        definition.weekdays.contains((calendar.component(.weekday, from: date) + 5) % 7 + 1)
    }
    public func streak(at now: Date, calendar: Calendar = .current) -> Int {
        var date = calendar.startOfDay(for: now)
        if count(on: date, calendar: calendar) < max(1, definition.target) {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var streak = 0
        for _ in 0..<730 {
            if isScheduled(on: date, calendar: calendar) {
                guard count(on: date, calendar: calendar) >= max(1, definition.target) else { break }
                streak += 1
            }
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return streak
    }
}
public struct SharedHabits: Codable, Equatable, Sendable {
    public var habits: [HabitRecord] = []
    public var title = "Piccoli passi, ogni giorno"
    public var showCompleted = true
    public init() {}
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public mutating func toggle(_ id: UUID, on date: Date = .now, calendar: Calendar = .current) {
        guard let index = habits.firstIndex(where: { $0.id == id }), habits[index].isScheduled(on: date, calendar: calendar) else { return }
        let key = Self.dayKey(date, calendar: calendar)
        let current = habits[index].days[key] ?? 0
        habits[index].days[key] = current >= max(1, habits[index].definition.target) ? 0 : current + 1
    }
    /// Apply definitions only; retain check-ins written by the other app while settings were open.
    public mutating func configure(_ definitions: [HabitDefinition], title: String, showCompleted: Bool) {
        habits = definitions.map { definition in
            var record = habits.first { $0.id == definition.id } ?? HabitRecord(definition: definition)
            record.definition = definition; return record
        }
        self.title = title; self.showCompleted = showCompleted
    }
}

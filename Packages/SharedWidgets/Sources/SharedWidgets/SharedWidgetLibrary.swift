import Foundation

@MainActor
public final class SharedWidgetLibrary {
    public static let shared = SharedWidgetLibrary()
    public let note: SharedWidgetChannel<SharedNote>
    public let timetable: SharedWidgetChannel<SharedTimetable>

    public init(directory: URL = SharedWidgetPaths.directory, migrateLegacy: Bool = true) {
        note = SharedWidgetChannel(key: "quick-note", initial: SharedNote(), directory: directory)
        timetable = SharedWidgetChannel(key: "timetable", initial: SharedTimetable(), directory: directory)
        guard migrateLegacy else { return }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchDeck", isDirectory: true)
        if let data = try? Data(contentsOf: legacy.appendingPathComponent("quick-note.json")),
           let text = try? JSONDecoder().decode(String.self, from: data) {
            try? note.update { $0.migrate(source: "NotchDeck", text: text) }
        }
        if let data = try? Data(contentsOf: legacy.appendingPathComponent("timetable.json")),
           let previous = try? JSONDecoder().decode(SharedTimetable.self, from: data),
           timetable.value.migratedSources?.contains("NotchDeck") != true {
            try? timetable.update { value in
                guard value.migratedSources?.contains("NotchDeck") != true else { return }
                if value.timetable == nil && value.pdf == nil {
                    value.timetable = previous.timetable; value.userData = previous.userData
                }
                var sources = value.migratedSources ?? []
                sources.insert("NotchDeck"); value.migratedSources = sources
            }
        }
    }
}

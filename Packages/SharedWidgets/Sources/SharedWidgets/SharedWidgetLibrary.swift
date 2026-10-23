import Foundation

@MainActor
public final class SharedWidgetLibrary {
    public static let shared = SharedWidgetLibrary()
    public let note: SharedWidgetChannel<SharedNote>
    public let timetable: SharedWidgetChannel<SharedTimetable>
    public let focus: SharedWidgetChannel<SharedFocus>
    public let shelf: SharedWidgetChannel<SharedShelf>
    public let music: SharedWidgetChannel<SharedMusic>
    public let countdown: SharedWidgetChannel<SharedCountdown>
    public let habits: SharedWidgetChannel<SharedHabits>
    public let directory: URL
    public lazy var focusController = SharedFocusController(channel: focus)
    public lazy var shelfController = SharedShelfController(channel: shelf, directory: directory)
    public lazy var musicController = SharedMusicController(channel: music)

    public init(directory: URL = SharedWidgetPaths.directory, migrateLegacy: Bool = true) {
        self.directory = directory
        note = SharedWidgetChannel(key: "quick-note", initial: SharedNote(), directory: directory)
        timetable = SharedWidgetChannel(key: "timetable", initial: SharedTimetable(), directory: directory)
        focus = SharedWidgetChannel(key: "focus", initial: SharedFocus(), directory: directory)
        shelf = SharedWidgetChannel(key: "file-shelf", initial: SharedShelf(), directory: directory)
        music = SharedWidgetChannel(key: "music", initial: SharedMusic(), directory: directory)
        countdown = SharedWidgetChannel(key: "countdown", initial: SharedCountdown(), directory: directory)
        habits = SharedWidgetChannel(key: "habits", initial: SharedHabits(), directory: directory)
        guard migrateLegacy else { return }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchDeck", isDirectory: true)
        if !focus.value.migratedLegacy,
           let data = try? Data(contentsOf: legacy.appendingPathComponent("pomodoro.json")),
           let engine = try? JSONDecoder().decode(FocusEngine.self, from: data) {
            try? focus.update {
                guard !$0.migratedLegacy else { return }
                if $0.engine == FocusEngine() { $0.engine = engine }
                $0.migratedLegacy = true
            }
        }
        if !shelf.value.migratedLegacy,
           let data = try? Data(contentsOf: legacy.appendingPathComponent("FileShelf/manifest.json")),
           let items = try? JSONDecoder().decode([SharedShelfItem].self, from: data) {
            try? shelf.update {
                guard !$0.migratedLegacy else { return }
                for item in items { $0.add(item) }
                $0.migratedLegacy = true
            }
        }
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

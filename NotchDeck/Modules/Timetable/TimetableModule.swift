import Foundation

/// The Timetable as a top-level NotchDeck workspace (shown beside Utilities,
/// Agents and FaceKey) once the module is enabled in Settings → Modules. It
/// needs no sensitive capability: the timetable is a local file the user
/// imports, and nothing leaves the Mac.
enum TimetableModule {
    static let identifier = "built-in.timetable"

    static let descriptor = ModuleDescriptor(
        identifier: identifier,
        displayName: "Timetable",
        summary: "Your weekly lesson timetable, with course notes and exams, in its own workspace.",
        version: "1.0.0",
        author: "NotchDeck",
        category: .productivity,
        iconSystemName: "calendar",
        defaultEnabled: false,
        surfaces: [.workspace, .settingsSection],
        capabilities: [],
        hasSettings: true)

    /// Single source of truth for whether the Timetable workspace is shown.
    static func isEnabled(_ settings: AppSettings) -> Bool {
        ModuleEnablement.isEnabled(identifier, defaultEnabled: descriptor.defaultEnabled, settings: settings)
    }
}

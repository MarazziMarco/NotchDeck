import Foundation
import Combine

/// Observable owner of `AppSettings`. Persists to UserDefaults as a single
/// JSON blob, debounced to avoid thrashing on rapid slider changes.
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private let defaults: UserDefaults
    private let key = "com.notchdeck.settings.v1"
    private var saveWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    /// Test/preview convenience with in-memory settings.
    static func inMemory(_ settings: AppSettings = AppSettings()) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "notchdeck.preview")!)
        store.settings = settings
        return store
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    // Convenience accessors used across the app.
    func isModuleEnabled(_ id: String, default def: Bool) -> Bool {
        settings.moduleEnabled[id] ?? def
    }

    func setModuleEnabled(_ id: String, _ enabled: Bool) {
        settings.moduleEnabled[id] = enabled
    }

    /// Authoritative Agents-workspace enablement (see `AgentsModule`).
    var agentsEnabled: Bool { AgentsModule.isEnabled(settings) }
}

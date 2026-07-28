import Foundation
import Combine

/// Observable owner of `AppSettings`. Persists to UserDefaults as a single
/// JSON blob, debounced to avoid thrashing on rapid slider changes.
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private let defaults: UserDefaults
    static let storageKey = "com.notchdeck.settings.v1"
    private let key = SettingsStore.storageKey
    private var saveWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = Self.decodeMigrating(data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private static func decodeMigrating(_ data: Data) -> AppSettings? {
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(AppSettings()),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaultsData)
                as? [String: Any] else {
            return nil
        }
        // Additive schema migration: preserve every stored value and supply only
        // keys introduced by newer builds. This prevents one new setting from
        // resetting unrelated preferences.
        for (key, value) in defaultObject where object[key] == nil {
            object[key] = value
        }
        guard let migrated = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: migrated)
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

    /// Applies one atomic Home edit, normalizes it against stable catalogue
    /// metadata, and flushes immediately so dismissal or termination cannot lose it.
    func updateHomeLayout(definitions: [HomeModuleDefinition],
                          _ update: (inout AppSettings) -> Void) {
        var next = settings
        HomeLayoutNormalizer.normalize(&next, definitions: definitions)
        update(&next)
        HomeLayoutNormalizer.normalize(&next, definitions: definitions)
        settings = next
        saveNow()
    }

    /// Applies one atomic More edit, normalized against stable More metadata, and
    /// flushes immediately. Operates ONLY on `moreLayout` (+ the shared
    /// `moduleEnabled` for placement); never touches any Home field.
    func updateMoreLayout(definitions: [MoreModuleDescriptor],
                          _ update: (inout AppSettings) -> Void) {
        var next = settings
        if next.moreLayout.placedIDs == nil {
            next.moreLayout.placedIDs = definitions.filter {
                next.moduleEnabled[$0.id] ?? $0.defaultPlaced
            }.map(\.id)
        }
        MoreLayoutNormalizer.normalize(&next.moreLayout, definitions: definitions)
        update(&next)
        MoreLayoutNormalizer.normalize(&next.moreLayout, definitions: definitions)
        settings = next
        saveNow()
    }

    /// Authoritative Agents-workspace enablement (see `AgentsModule`).
    var agentsEnabled: Bool { AgentsModule.isEnabled(settings) }
}

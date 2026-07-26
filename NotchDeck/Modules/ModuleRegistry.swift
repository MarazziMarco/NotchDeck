import SwiftUI
import Combine

/// Central catalogue of modules plus the user's library (enabled) and Home
/// (favorites, order, sizes) preferences. All data-driven off `SettingsStore`.
final class ModuleRegistry: ObservableObject {
    let allModules: [NotchModule]

    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    /// Enabled + available modules, in library order.
    @Published private(set) var libraryModules: [NotchModule] = []
    /// Favorites shown on Home, in the user's order.
    @Published private(set) var homeModules: [NotchModule] = []

    init(modules: [NotchModule], settings: SettingsStore) {
        self.allModules = modules
        self.settings = settings
        recompute()
        settings.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    func module(id: String) -> NotchModule? { allModules.first { $0.id == id } }

    /// Group a module belongs to (user override or its default).
    func group(of module: NotchModule) -> ModuleGroup {
        settings.settings.moduleGroupAssignment[module.id]
            .flatMap(ModuleGroup.init(rawValue:)) ?? module.defaultGroup
    }

    /// Enabled modules assigned to a Utilities group, in library order.
    func modules(in group: ModuleGroup) -> [NotchModule] {
        libraryModules.filter { self.group(of: $0) == group }
    }

    func assign(_ module: NotchModule, to group: ModuleGroup) {
        settings.settings.moduleGroupAssignment[module.id] = group.rawValue
        recompute()
    }

    func isEnabled(_ module: NotchModule) -> Bool {
        guard module.isAvailable else { return false }
        return settings.isModuleEnabled(module.id, default: module.defaultEnabled)
    }

    func isHomeFavorite(_ module: NotchModule) -> Bool {
        homeFavoriteIDs.contains(module.id)
    }

    func size(for module: NotchModule) -> ModuleDashboardSize {
        settings.settings.homeSizes[module.id] ?? module.defaultDashboardSize
    }

    // MARK: Derived

    private var homeFavoriteIDs: [String] {
        if let favorites = settings.settings.homeFavorites { return favorites }
        // First run: default favorites from module metadata.
        return allModules.filter { $0.defaultHomeFavorite && isEnabled($0) }
            .sorted { $0.defaultPriority < $1.defaultPriority }
            .map(\.id)
    }

    private func recompute() {
        let byID = Dictionary(uniqueKeysWithValues: allModules.map { ($0.id, $0) })

        // Library order.
        var lib: [NotchModule] = []
        var seen = Set<String>()
        for id in settings.settings.moduleOrder {
            if let m = byID[id], !seen.contains(id) { lib.append(m); seen.insert(id) }
        }
        lib.append(contentsOf: allModules.filter { !seen.contains($0.id) }
            .sorted { $0.defaultPriority < $1.defaultPriority })
        libraryModules = lib.filter { isEnabled($0) }

        // Home = favorites (enabled + available), in order.
        homeModules = homeFavoriteIDs.compactMap { byID[$0] }.filter { isEnabled($0) }
    }

    // MARK: Mutations

    func setLibraryOrder(_ ids: [String]) { settings.settings.moduleOrder = ids; recompute() }

    func toggleEnabled(_ module: NotchModule, _ enabled: Bool) {
        settings.setModuleEnabled(module.id, enabled)
        if !enabled { removeFromHome(module) }
        recompute()
    }

    func setSize(_ module: NotchModule, _ size: ModuleDashboardSize) {
        settings.settings.homeSizes[module.id] = size
        recompute()
    }

    func addToHome(_ module: NotchModule) {
        var favorites = homeFavoriteIDs
        guard !favorites.contains(module.id) else { return }
        favorites.append(module.id)
        settings.settings.homeFavorites = favorites
        recompute()
    }

    func removeFromHome(_ module: NotchModule) {
        var favorites = homeFavoriteIDs
        favorites.removeAll { $0 == module.id }
        settings.settings.homeFavorites = favorites
        recompute()
    }

    func setHomeOrder(_ ids: [String]) {
        settings.settings.homeFavorites = ids
        recompute()
    }

    func moveHome(from source: IndexSet, to destination: Int) {
        var ids = homeModules.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        setHomeOrder(ids)
    }
}

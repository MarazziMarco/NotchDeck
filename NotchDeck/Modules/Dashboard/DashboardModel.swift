import SwiftUI
import Combine

/// Pomodoro widget appearance (engine untouched).
enum PomodoroWidgetStyle: String, Codable, CaseIterable, Identifiable {
    case minimal, tomato, monochrome
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Initial dashboard presets.
enum DashboardPreset: String, CaseIterable, Identifiable {
    case balanced, productivity, media, minimal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Ordered (moduleID, size) for the preset. Only applied for available modules.
    var widgets: [(id: String, size: DashboardWidgetSize)] {
        switch self {
        case .balanced:
            return [("clipboard", .wide), ("pomodoro", .small), ("mirror", .small),
                    ("nowPlaying", .medium), ("fileShelf", .small)]
        case .productivity:
            return [("clipboard", .wide), ("pomodoro", .small), ("quickNote", .medium),
                    ("fileShelf", .small)]
        case .media:
            return [("nowPlaying", .wide), ("mirror", .medium), ("clipboard", .small)]
        case .minimal:
            return [("clipboard", .medium), ("pomodoro", .small)]
        }
    }
}

/// Owns the widget-dashboard placement per layout class, resolves grid cells,
/// and mutates + persists placements. All data-driven — no module switch.
@MainActor
final class DashboardModel: ObservableObject {
    @Published var customizing = false

    private let settings: SettingsStore
    private let registry: ModuleRegistry

    init(settings: SettingsStore, registry: ModuleRegistry) {
        self.settings = settings
        self.registry = registry
    }

    // MARK: Placement snapshots (per layout class)

    func placements(for layoutClass: NotchLayoutClass) -> [DashboardWidgetPlacement] {
        let key = layoutClass.rawValue
        if let stored = settings.settings.widgetPlacements[key], !stored.isEmpty {
            return normalized(stored)
        }
        return defaultPlacements()
    }

    private func normalized(_ list: [DashboardWidgetPlacement]) -> [DashboardWidgetPlacement] {
        // Drop placements for modules that no longer exist / are disabled.
        list.filter { p in registry.module(id: p.moduleID).map { registry.isEnabled($0) } ?? false }
            .sorted { $0.order < $1.order }
    }

    /// First-run defaults: the curated Home-group modules (Note, Mirror, Now
    /// Playing, File Shelf) at their default widget sizes.
    private func defaultPlacements() -> [DashboardWidgetPlacement] {
        registry.modules(in: .home).enumerated().map { idx, module in
            DashboardWidgetPlacement(moduleID: module.id, order: idx,
                                     size: module.defaultWidgetSize)
        }
    }

    private func save(_ list: [DashboardWidgetPlacement], for layoutClass: NotchLayoutClass) {
        settings.settings.widgetPlacements[layoutClass.rawValue] = list
        objectWillChange.send()
    }

    // MARK: Resolve to grid cells

    func resolved(for layoutClass: NotchLayoutClass) -> GridSolver.Result {
        let columns = DashboardGrid.columns(for: layoutClass)
        let items = placements(for: layoutClass).filter(\.isVisible).map {
            GridSolver.Item(id: $0.moduleID, w: $0.size.colSpan, h: $0.size.rowSpan,
                            preferredCol: $0.preferredColumn, preferredRow: $0.preferredRow)
        }
        return GridSolver.solve(items: items, columns: columns)
    }

    // MARK: Mutations

    func module(id: String) -> NotchModule? { registry.module(id: id) }

    func isSizeValid(_ moduleID: String, _ size: DashboardWidgetSize) -> Bool {
        registry.module(id: moduleID)?.supportedWidgetSizes.contains(size) ?? false
    }

    func setSize(_ moduleID: String, _ size: DashboardWidgetSize, for layoutClass: NotchLayoutClass) {
        guard isSizeValid(moduleID, size) else { return }
        var list = placements(for: layoutClass)
        guard let idx = list.firstIndex(where: { $0.moduleID == moduleID }) else { return }
        list[idx].size = size
        list[idx].preferredColumn = nil; list[idx].preferredRow = nil   // let it re-snap
        save(list, for: layoutClass)
    }

    func move(_ moduleID: String, toOrder newOrder: Int, for layoutClass: NotchLayoutClass) {
        var list = placements(for: layoutClass)
        guard let idx = list.firstIndex(where: { $0.moduleID == moduleID }) else { return }
        let item = list.remove(at: idx)
        let clamped = max(0, min(newOrder, list.count))
        list.insert(item, at: clamped)
        for i in list.indices {
            list[i].order = i
            list[i].preferredColumn = nil; list[i].preferredRow = nil
        }
        save(list, for: layoutClass)
    }

    func setPreferredCell(_ moduleID: String, col: Int, row: Int, for layoutClass: NotchLayoutClass) {
        var list = placements(for: layoutClass)
        guard let idx = list.firstIndex(where: { $0.moduleID == moduleID }) else { return }
        list[idx].preferredColumn = col
        list[idx].preferredRow = row
        save(list, for: layoutClass)
    }

    func addWidget(_ moduleID: String, for layoutClass: NotchLayoutClass) {
        guard let module = registry.module(id: moduleID) else { return }
        var list = placements(for: layoutClass)
        guard !list.contains(where: { $0.moduleID == moduleID }) else { return }
        list.append(DashboardWidgetPlacement(moduleID: moduleID, order: list.count,
                                             size: module.defaultWidgetSize))
        save(list, for: layoutClass)
    }

    func remove(_ moduleID: String, for layoutClass: NotchLayoutClass) {
        var list = placements(for: layoutClass).filter { $0.moduleID != moduleID }
        for i in list.indices { list[i].order = i }
        save(list, for: layoutClass)
    }

    func applyPreset(_ preset: DashboardPreset, for layoutClass: NotchLayoutClass) {
        let list = preset.widgets.enumerated().compactMap { idx, w -> DashboardWidgetPlacement? in
            guard let module = registry.module(id: w.id), registry.isEnabled(module) else { return nil }
            let size = module.supportedWidgetSizes.contains(w.size) ? w.size : module.defaultWidgetSize
            return DashboardWidgetPlacement(moduleID: w.id, order: idx, size: size)
        }
        save(list, for: layoutClass)
    }

    func reset(for layoutClass: NotchLayoutClass) {
        settings.settings.widgetPlacements[layoutClass.rawValue] = nil
        objectWillChange.send()
    }

    /// Whether the current placements differ from a clean preset (for confirm).
    func hasCustomPlacements(for layoutClass: NotchLayoutClass) -> Bool {
        !(settings.settings.widgetPlacements[layoutClass.rawValue]?.isEmpty ?? true)
    }
}

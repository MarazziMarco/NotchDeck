import Foundation

/// Stable catalogue metadata used by Home. This is derived from built-in module
/// declarations and is never persisted as another layout model.
struct HomeModuleDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let defaultPriority: Int
    let defaultVisible: Bool
    let supportedSizes: [EditorialZoneWidth]
    let defaultSize: EditorialZoneWidth
}

/// The product rule for Customize Home eligibility.
enum HomeModuleEligibility {
    static func isEligible(source: ModuleSource, declaredGroup: ModuleGroup?,
                           surfaces: Set<ModuleSurface>) -> Bool {
        source == .builtIn
            && declaredGroup == .home
            && surfaces.contains(.homeCard)
            && !surfaces.contains(.workspace)
    }

    /// ModuleRegistry contains built-ins only. Eligibility comes from immutable
    /// module metadata, never current enablement, placement, order or assignment.
    static func definitions(from modules: [NotchModule]) -> [HomeModuleDefinition] {
        let eligible = modules.filter {
            isEligible(source: .builtIn, declaredGroup: $0.defaultGroup, surfaces: [.homeCard])
        }
        let byID = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })
        let known = EditorialHomeLayout.defaultOrder.compactMap { byID[$0] }
        let knownIDs = Set(known.map(\.id))
        let future = eligible.filter { !knownIDs.contains($0.id) }
            .sorted {
                if $0.defaultPriority != $1.defaultPriority {
                    return $0.defaultPriority < $1.defaultPriority
                }
                return $0.id < $1.id
            }
        return (known + future).map { module in
            var sizes: [EditorialZoneWidth] = []
            for size in module.supportedSizes {
                let mapped = EditorialZoneWidth(size)
                if !sizes.contains(mapped) { sizes.append(mapped) }
            }
            let fallback = sizes.first ?? .standard
            let preferred = EditorialZoneWidth(module.defaultDashboardSize)
            return HomeModuleDefinition(
                id: module.id, name: module.displayName, icon: module.iconName,
                defaultPriority: module.defaultPriority,
                defaultVisible: module.defaultEnabled,
                supportedSizes: sizes.isEmpty ? [fallback] : sizes,
                defaultSize: sizes.contains(preferred) ? preferred : fallback)
        }
    }
}

/// One normalization and mutation boundary for the existing authoritative Home
/// settings. No persistent draft, indexes or second placement array is created.
enum HomeLayoutNormalizer {
    static func normalize(_ settings: inout AppSettings,
                          definitions: [HomeModuleDefinition]) {
        let definitions = uniqueDefinitions(definitions)
        let eligible = Set(definitions.map(\.id))
        let defaults = defaultOrder(definitions)

        var seen = Set<String>()
        let stored = settings.editorialOrder ?? []
        var order = stored.filter { eligible.contains($0) && seen.insert($0).inserted }
        let inserted = defaults.filter { seen.insert($0).inserted }
        order.append(contentsOf: inserted)
        settings.editorialOrder = order

        // Migrate the old competing Home-only visibility source into the
        // authoritative module enablement map, then retire it.
        for id in settings.editorialHidden where eligible.contains(id) {
            settings.moduleEnabled[id] = false
        }
        settings.editorialHidden = []

        var widths: [String: EditorialZoneWidth] = [:]
        for definition in definitions {
            let stored = settings.editorialWidths[definition.id]
            widths[definition.id] = normalizedSize(stored, definition: definition)
        }
        settings.editorialWidths = widths

        if let favorites = settings.homeFavorites {
            seen.removeAll()
            settings.homeFavorites = favorites.filter {
                eligible.contains($0) && seen.insert($0).inserted
            }
        }
        settings.homeSizes = settings.homeSizes.filter { id, size in
            guard let definition = definitions.first(where: { $0.id == id }) else { return false }
            return definition.supportedSizes.contains(EditorialZoneWidth(size))
        }

        for key in settings.widgetPlacements.keys {
            let storedPlacements = settings.widgetPlacements[key] ?? []
            seen.removeAll()
            var placements = storedPlacements
                .sorted { $0.order < $1.order }
                .filter { eligible.contains($0.moduleID) && seen.insert($0.moduleID).inserted }
            for index in placements.indices {
                placements[index].id = placements[index].moduleID
                placements[index].order = index
            }
            settings.widgetPlacements[key] = placements
        }
    }

    static func needsNormalization(_ settings: AppSettings,
                                   definitions: [HomeModuleDefinition]) -> Bool {
        var normalized = settings
        normalize(&normalized, definitions: definitions)
        return normalized != settings
    }

    /// Compatibility for the community-routing migration tests. New code should
    /// pass full definitions so missing modules and sizes can also be normalized.
    static func normalize(_ settings: inout AppSettings, eligible: Set<String>) {
        var seen = Set<String>()
        if let order = settings.editorialOrder {
            settings.editorialOrder = order.filter {
                eligible.contains($0) && seen.insert($0).inserted
            }
        }
        seen.removeAll()
        settings.editorialHidden = settings.editorialHidden.filter {
            eligible.contains($0) && seen.insert($0).inserted
        }
        settings.editorialWidths = settings.editorialWidths.filter {
            eligible.contains($0.key)
        }
        if let favorites = settings.homeFavorites {
            seen.removeAll()
            settings.homeFavorites = favorites.filter {
                eligible.contains($0) && seen.insert($0).inserted
            }
        }
        settings.homeSizes = settings.homeSizes.filter { eligible.contains($0.key) }
        for key in settings.widgetPlacements.keys {
            seen.removeAll()
            var placements = (settings.widgetPlacements[key] ?? [])
                .sorted { $0.order < $1.order }
                .filter { eligible.contains($0.moduleID) && seen.insert($0.moduleID).inserted }
            for index in placements.indices {
                placements[index].id = placements[index].moduleID
                placements[index].order = index
            }
            settings.widgetPlacements[key] = placements
        }
    }

    static func needsNormalization(_ settings: AppSettings, eligible: Set<String>) -> Bool {
        var normalized = settings
        normalize(&normalized, eligible: eligible)
        return normalized != settings
    }

    static func order(in settings: AppSettings,
                      definitions: [HomeModuleDefinition]) -> [String] {
        var copy = settings
        normalize(&copy, definitions: definitions)
        return copy.editorialOrder ?? []
    }

    static func visibleOrder(in settings: AppSettings,
                             definitions: [HomeModuleDefinition]) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues:
            uniqueDefinitions(definitions).map { ($0.id, $0) })
        return order(in: settings, definitions: definitions).filter {
            guard let definition = byID[$0] else { return false }
            return settings.moduleEnabled[$0] ?? definition.defaultVisible
        }
    }

    static func isVisible(_ id: String, in settings: AppSettings,
                          definitions: [HomeModuleDefinition]) -> Bool {
        guard let definition = uniqueDefinitions(definitions)
            .first(where: { $0.id == id }) else {
            return false
        }
        return settings.moduleEnabled[id] ?? definition.defaultVisible
    }

    static func size(_ id: String, in settings: AppSettings,
                     definitions: [HomeModuleDefinition]) -> EditorialZoneWidth? {
        guard let definition = uniqueDefinitions(definitions).first(where: { $0.id == id }) else {
            return nil
        }
        return normalizedSize(settings.editorialWidths[id], definition: definition)
    }

    static func setVisible(_ visible: Bool, id: String, in settings: inout AppSettings,
                           definitions: [HomeModuleDefinition]) {
        guard definitions.contains(where: { $0.id == id }) else { return }
        settings.moduleEnabled[id] = visible
        normalize(&settings, definitions: definitions)
    }

    static func setSize(_ size: EditorialZoneWidth, id: String,
                        in settings: inout AppSettings,
                        definitions: [HomeModuleDefinition]) {
        guard let definition = definitions.first(where: { $0.id == id }),
              definition.supportedSizes.contains(size) else { return }
        settings.editorialWidths[id] = size
        normalize(&settings, definitions: definitions)
    }

    static func move(_ id: String, before target: String,
                     in settings: inout AppSettings,
                     definitions: [HomeModuleDefinition]) {
        let ids = order(in: settings, definitions: definitions)
        settings.editorialOrder = HomeReorder.move(ids, drag: id, onto: target)
        normalize(&settings, definitions: definitions)
    }

    static func move(_ id: String, by delta: Int,
                     in settings: inout AppSettings,
                     definitions: [HomeModuleDefinition]) {
        let ids = order(in: settings, definitions: definitions)
        settings.editorialOrder = HomeReorder.shift(ids, id: id, by: delta)
        normalize(&settings, definitions: definitions)
    }

    static func move(from source: IndexSet, to destination: Int,
                     in settings: inout AppSettings,
                     definitions: [HomeModuleDefinition]) {
        var ids = order(in: settings, definitions: definitions)
        ids.move(fromOffsets: source, toOffset: destination)
        settings.editorialOrder = ids
        normalize(&settings, definitions: definitions)
    }

    static func reset(_ settings: inout AppSettings,
                      definitions: [HomeModuleDefinition]) {
        let definitions = uniqueDefinitions(definitions)
        settings.editorialOrder = defaultOrder(definitions)
        settings.editorialHidden = []
        settings.editorialWidths = Dictionary(uniqueKeysWithValues:
            definitions.map { ($0.id, $0.defaultSize) })
        for definition in definitions {
            settings.moduleEnabled[definition.id] = definition.defaultVisible
        }
        normalize(&settings, definitions: definitions)
    }

    private static func uniqueDefinitions(_ definitions: [HomeModuleDefinition])
        -> [HomeModuleDefinition] {
        var seen = Set<String>()
        return definitions.filter { seen.insert($0.id).inserted }
    }

    private static func defaultOrder(_ definitions: [HomeModuleDefinition]) -> [String] {
        let eligible = Set(definitions.map(\.id))
        var order = EditorialHomeLayout.defaultOrder.filter { eligible.contains($0) }
        let included = Set(order)
        order.append(contentsOf: definitions.filter { !included.contains($0.id) }
            .sorted {
                if $0.defaultPriority != $1.defaultPriority {
                    return $0.defaultPriority < $1.defaultPriority
                }
                return $0.id < $1.id
            }
            .map(\.id))
        return order
    }

    private static func normalizedSize(_ stored: EditorialZoneWidth?,
                                       definition: HomeModuleDefinition) -> EditorialZoneWidth {
        if let stored, definition.supportedSizes.contains(stored) { return stored }
        if definition.supportedSizes.contains(definition.defaultSize) { return definition.defaultSize }
        return definition.supportedSizes.first ?? .standard
    }
}

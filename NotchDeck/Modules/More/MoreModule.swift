import Foundation

// MARK: - More layout model (independent of Home)
//
// Placement authority: a module is "placed in More" iff it is eligible AND
// enabled (`AppSettings.moduleEnabled[id]`) — the SAME shared flag Settings →
// Modules toggles. This is intentional so enabling System Pulse in Settings and
// "Add" in the More Module Library are one action, with no duplicate placement
// state. The new `AppSettings.moreLayout` stores ONLY More-specific order + size;
// it never reads or writes any Home field.

/// Supported More card size variants and their grid spans (2-column grid).
enum MoreModuleSize: String, Codable, CaseIterable, Identifiable {
    case compact   // 1×1
    case wide      // 2×1
    case large     // 2×2
    var id: String { rawValue }
    var w: Int { self == .compact ? 1 : 2 }
    var h: Int { self == .large ? 2 : 1 }
    var label: String { rawValue.capitalized }
}

/// Immutable metadata for a module eligible for the More surface.
struct MoreModuleDescriptor: Equatable, Identifiable {
    let id: String
    let name: String
    let summary: String
    let iconSystemName: String
    let source: ModuleSource            // .builtIn or .community
    let supportedSizes: [MoreModuleSize]
    let defaultSize: MoreModuleSize

    func normalizedSize(_ requested: MoreModuleSize?) -> MoreModuleSize {
        if let requested, supportedSizes.contains(requested) { return requested }
        return supportedSizes.contains(defaultSize) ? defaultSize : (supportedSizes.first ?? .wide)
    }
}

/// Persisted More layout: ONLY order + per-module size. Placement (in/out of More)
/// is the shared `moduleEnabled` flag. Completely independent of Home persistence.
struct MoreLayoutSettings: Codable, Equatable {
    var order: [String]? = nil
    var sizes: [String: MoreModuleSize] = [:]
}

/// Which modules may appear on More, derived from the authoritative registries —
/// never inferred from a display name. Community/example modules are always More.
/// Built-in modules are More-eligible only when their registry metadata declares
/// the More group. Home-only and workspace modules are excluded.
enum MoreModuleEligibility {
    /// Default sizes by source (declared, not name-inferred): community cards are
    /// richer (wide/large); built-in More utilities are smaller (compact/wide).
    static func supportedSizes(for source: ModuleSource) -> [MoreModuleSize] {
        source == .community || source == .example ? [.wide, .large] : [.compact, .wide]
    }
    static func defaultSize(for source: ModuleSource) -> MoreModuleSize {
        source == .community || source == .example ? .wide : .compact
    }
}

/// Pure normalizer for the More layout — analogous to HomeLayoutNormalizer but
/// touching ONLY `moreLayout`. Drops unknown/obsolete ids, de-duplicates, keeps a
/// valid user order, inserts newly-eligible modules deterministically, and
/// validates sizes against each descriptor's supported set.
enum MoreLayoutNormalizer {
    /// Deterministic default order: community first (registration order), then
    /// built-in More modules, as provided by the eligible descriptor list.
    static func defaultOrder(_ definitions: [MoreModuleDescriptor]) -> [String] {
        var seen = Set<String>()
        return definitions.map(\.id).filter { seen.insert($0).inserted }
    }

    static func normalize(_ layout: inout MoreLayoutSettings, definitions: [MoreModuleDescriptor]) {
        let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let eligible = Set(byID.keys)

        // Order: keep valid ids in user order (dedup), then append any newly
        // eligible module not yet present at a deterministic position.
        var seen = Set<String>()
        var order = (layout.order ?? []).filter { eligible.contains($0) && seen.insert($0).inserted }
        for id in defaultOrder(definitions) where !seen.contains(id) { order.append(id); seen.insert(id) }
        layout.order = order

        // Sizes: drop unknown ids; clamp each to the module's supported sizes.
        var sizes: [String: MoreModuleSize] = [:]
        for id in order {
            guard let d = byID[id] else { continue }
            sizes[id] = d.normalizedSize(layout.sizes[id])
        }
        layout.sizes = sizes
    }

    static func needsNormalization(_ layout: MoreLayoutSettings, definitions: [MoreModuleDescriptor]) -> Bool {
        var copy = layout
        normalize(&copy, definitions: definitions)
        return copy != layout
    }

    /// Order of the modules currently PLACED (eligible + enabled), normalized.
    static func placedOrder(_ layout: MoreLayoutSettings, definitions: [MoreModuleDescriptor],
                            isEnabled: (String) -> Bool) -> [String] {
        var copy = layout
        normalize(&copy, definitions: definitions)
        return (copy.order ?? []).filter(isEnabled)
    }

    static func size(_ id: String, in layout: MoreLayoutSettings,
                     definitions: [MoreModuleDescriptor]) -> MoreModuleSize {
        let d = definitions.first { $0.id == id }
        return d?.normalizedSize(layout.sizes[id]) ?? .wide
    }
}

// MARK: - Grid solver (2-column, deterministic; delegates to GridSolver)

/// Deterministic 2-column packing for More cards. Reuses the proven `GridSolver`
/// (which already supports multi-row cells) with a fixed 2-column grid, so a
/// `large` (2×2) card and a mix of `compact`/`wide` cards pack without overlap or
/// horizontal scrolling.
enum MoreGridSolver {
    static let columns = 2

    struct Item: Equatable {
        let id: String
        let size: MoreModuleSize
    }

    static func solve(_ items: [Item], columns: Int = MoreGridSolver.columns) -> GridSolver.Result {
        GridSolver.solve(
            items: items.map { GridSolver.Item(id: $0.id, w: min($0.size.w, columns), h: $0.size.h) },
            columns: columns,
            maxRows: 200)   // More scrolls vertically; no hard page cap
    }

    static func overlaps(_ a: GridCell, _ b: GridCell) -> Bool { GridSolver.overlaps(a, b) }
}

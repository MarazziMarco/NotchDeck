import SwiftUI

/// Where a catalogue entry comes from.
enum ModuleSource: String, Equatable {
    case builtIn, community, example
    var label: String {
        switch self { case .builtIn: return "Built-in"; case .community: return "Community"; case .example: return "Example" }
    }
}

/// One unified catalogue entry (built-in adapter OR community/example module).
struct ModuleCatalogEntry: Identifiable, Equatable {
    let descriptor: ModuleDescriptor
    let source: ModuleSource
    var id: String { descriptor.identifier }

    /// Does this entry surface on Home? Only BUILT-IN modules that explicitly
    /// declare `.homeCard` are Home modules — Community and workspace modules are
    /// never Home cards (see `ModuleSurfaceRouting`).
    var isHomeModule: Bool { ModuleSurfaceRouting.rendersInHome(descriptor, source: source) }

    /// Does this entry render in the More secondary-utility surface?
    var isMoreModule: Bool { ModuleSurfaceRouting.rendersInMore(descriptor, source: source) }
}

/// THE authoritative surface-routing rule, enforced centrally for every current
/// and future module — not a per-module special case.
///
///   ModuleSource.community  → More only, NEVER Home.
///   Built-in                → Home only when it explicitly declares `.homeCard`.
///   Workspace (Agents)      → neither Home nor More.
enum ModuleSurfaceRouting {
    /// Community (and, when surfaced, developer example) modules live in More.
    static func rendersInMore(_ d: ModuleDescriptor, source: ModuleSource) -> Bool {
        guard !d.surfaces.contains(.workspace) else { return false }
        if source == .community || source == .example { return true }
        return d.surfaces.contains(.more)
    }

    /// Only a built-in module that declares `.homeCard` renders on Home. A
    /// Community module's obsolete `.homeCard` declaration is ignored here.
    static func rendersInHome(_ d: ModuleDescriptor, source: ModuleSource) -> Bool {
        source == .builtIn && d.surfaces.contains(.homeCard) && !d.surfaces.contains(.workspace)
    }
}

/// Bridges a legacy `NotchModule` into a `ModuleDescriptor` for the catalogue —
/// without touching the module's working view/service. Pure + testable.
enum LegacyModuleAdapter {
    static func descriptor(id: String, name: String, icon: String, defaultEnabled: Bool,
                           hasSettings: Bool) -> ModuleDescriptor {
        ModuleDescriptor(
            identifier: id, displayName: name, summary: summary(for: id), version: "1.0.0",
            author: "NotchDeck", category: category(for: id), iconSystemName: icon,
            defaultEnabled: defaultEnabled, surfaces: surfaces(for: id, hasSettings: hasSettings),
            capabilities: capabilities(for: id), hasSettings: hasSettings)
    }

    static func capabilities(for id: String) -> Set<ModuleCapability> {
        switch id {
        case "mirror": return [.camera]
        case "screenshot", "screen": return [.screenRecording]
        case "downloads": return [.downloadsAccess]
        case "fileShelf": return [.selectedFolderAccess]
        case "nowPlaying": return [.mediaControl]
        default: return []
        }
    }
    static func category(for id: String) -> ModuleCategoryKind {
        switch id {
        case "fileShelf", "downloads", "screenshot", "clipboard": return .files
        case "nowPlaying", "mirror": return .media
        case "pomodoro": return .productivity
        default: return .system
        }
    }
    private static func surfaces(for id: String, hasSettings: Bool) -> Set<ModuleSurface> {
        var s: Set<ModuleSurface> = [.homeCard]
        if hasSettings { s.insert(.settingsSection) }
        return s
    }
    private static func summary(for id: String) -> String {
        switch id {
        case "quickNote": return "A quick sticky note."
        case "nowPlaying": return "Current track and playback controls."
        case "fileShelf": return "Temporary staging area for files."
        case "mirror": return "A live camera preview (never recorded)."
        case "pomodoro": return "A focus timer with work/break cycles."
        case "downloads": return "In-progress and today's downloads."
        case "screenshot": return "Capture the screen."
        case "clipboard": return "Recent clipboard history."
        default: return "A NotchDeck module."
        }
    }
}

/// The authoritative unified module catalogue. Pure with respect to Settings
/// views — it takes descriptors + an enablement store, so it is testable without
/// launching the panel.
struct ModuleCatalog: Equatable {
    private(set) var entries: [ModuleCatalogEntry]

    init(builtIn: [ModuleDescriptor], community: [ModuleDescriptor],
         example: [ModuleDescriptor], includeExample: Bool) {
        var seen = Set<String>()
        var out: [ModuleCatalogEntry] = []
        func add(_ ds: [ModuleDescriptor], _ src: ModuleSource) {
            for d in ds.sorted(by: { $0.displayName < $1.displayName }) where seen.insert(d.identifier).inserted {
                out.append(ModuleCatalogEntry(descriptor: d, source: src))
            }
        }
        add(builtIn, .builtIn)          // built-in first, then community, then example
        add(community, .community)
        if includeExample { add(example, .example) }
        self.entries = out
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, enabled, builtIn, community
        var id: String { rawValue }
        var label: String {
            switch self { case .all: return "All"; case .enabled: return "Enabled"
                          case .builtIn: return "Built-in"; case .community: return "Community" }
        }
    }

    /// Search + filter. `isEnabled` resolves the authoritative enabled state.
    func filtered(search: String, filter: Filter, isEnabled: (ModuleCatalogEntry) -> Bool) -> [ModuleCatalogEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { e in
            let matches = q.isEmpty
                || e.descriptor.displayName.lowercased().contains(q)
                || e.descriptor.summary.lowercased().contains(q)
            guard matches else { return false }
            switch filter {
            case .all: return true
            case .enabled: return isEnabled(e)
            case .builtIn: return e.source == .builtIn
            case .community: return e.source == .community
            }
        }
    }

    func entry(id: String) -> ModuleCatalogEntry? { entries.first { $0.id == id } }
}

/// ONE authoritative enabled-state bridge. `moduleEnabled` is the source of
/// truth; Home placement (`editorialOrder`) is preserved across toggles. Pure
/// over `AppSettings` for testability.
enum ModuleEnablement {
    static func isEnabled(_ id: String, defaultEnabled: Bool, settings: AppSettings) -> Bool {
        settings.moduleEnabled[id] ?? defaultEnabled
    }

    static func setEnabled(_ id: String, _ enabled: Bool, isHomeModule: Bool,
                           defaultOrder: [String], in settings: inout AppSettings) {
        settings.moduleEnabled[id] = enabled
        guard isHomeModule else { return }
        if enabled {
            // Give it a Home placement slot without disturbing existing order.
            var order = settings.editorialOrder ?? defaultOrder
            if !order.contains(id) { order.append(id); settings.editorialOrder = order }
            settings.editorialHidden.removeAll { $0 == id }
        }
        // Disable keeps moduleEnabled=false and the order slot (placement/size
        // preserved for re-enable). Rendering is gated by moduleEnabled.
    }
}

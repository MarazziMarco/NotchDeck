import SwiftUI

/// One eligible More module: its metadata + a card renderer, built from the
/// authoritative registries (never a parallel hard-coded list).
struct MoreModuleView: Identifiable {
    let descriptor: MoreModuleDescriptor
    let card: (MoreModuleSize) -> AnyView
    var id: String { descriptor.id }
}

/// Bridges the built-in `ModuleRegistry` and the `CommunityModuleRegistry` into
/// the More module model. Community/example modules are always More-eligible;
/// built-in modules only when their registry group is `.more` (declared metadata,
/// never name-inferred). Home-only and workspace modules never appear.
@MainActor
enum MoreCatalog {
    /// Map a More size onto the legacy dashboard-card size for built-in modules.
    static func dashboardSize(_ size: MoreModuleSize) -> ModuleDashboardSize {
        switch size { case .compact: return .small; case .wide: return .medium; case .large: return .large }
    }

    static func views(registry: ModuleRegistry, community: CommunityModuleRegistry) -> [MoreModuleView] {
        var out: [MoreModuleView] = []

        // Community first (registration order).
        for module in community.modules {
            let d = module.descriptor
            let desc = MoreModuleDescriptor(
                id: d.identifier, name: d.displayName, summary: d.summary,
                iconSystemName: d.iconSystemName, source: .community,
                supportedSizes: MoreModuleEligibility.supportedSizes(for: .community),
                defaultSize: MoreModuleEligibility.defaultSize(for: .community))
            out.append(MoreModuleView(descriptor: desc) { _ in
                module.homeCard() ?? AnyView(EmptyView())
            })
        }

        // Built-in modules whose registry metadata declares the More group.
        for module in registry.allModules where module.defaultGroup == .more {
            let desc = MoreModuleDescriptor(
                id: module.id, name: module.displayName, summary: "",
                iconSystemName: module.iconName, source: .builtIn,
                supportedSizes: MoreModuleEligibility.supportedSizes(for: .builtIn),
                defaultSize: MoreModuleEligibility.defaultSize(for: .builtIn))
            out.append(MoreModuleView(descriptor: desc) { size in
                module.makeDashboardCard(size: dashboardSize(size))
            })
        }
        return out
    }

    static func descriptors(registry: ModuleRegistry, community: CommunityModuleRegistry) -> [MoreModuleDescriptor] {
        views(registry: registry, community: community).map(\.descriptor)
    }

    /// Whether a module is currently placed (enabled) in More. Uses the shared
    /// authoritative `moduleEnabled` flag, defaulting to each descriptor's source.
    static func isPlaced(_ descriptor: MoreModuleDescriptor, settings: AppSettings) -> Bool {
        // Community modules ship disabled; built-in `.more` modules default enabled.
        let def = descriptor.source == .builtIn
        return ModuleEnablement.isEnabled(descriptor.id, defaultEnabled: def, settings: settings)
    }
}

import Foundation

enum ModuleRegistryError: Error, Equatable {
    case duplicateIdentifier(String)
}

/// One authoritative registry for community-extensible `NotchDeckModule`s.
///
/// - Registers built-in, community and example modules.
/// - Rejects duplicate identifiers.
/// - Preserves deterministic ordering.
/// - Exposes enabled/disabled state and metadata for Settings.
/// - Supports future identifier migration via `alias`.
/// - Fully testable without opening the panel.
///
/// This is SEPARATE from the existing `ModuleRegistry` that drives the shipped
/// built-in widgets, so no existing feature is rewritten.
@MainActor
final class CommunityModuleRegistry {
    private(set) var modules: [AnyNotchDeckModule] = []
    private var index: [String: Int] = [:]           // identifier → position
    private var aliases: [String: String] = [:]      // old identifier → current
    private var disabled: Set<String> = []

    init() {}

    /// Register a module type. Throws on a duplicate identifier so two modules
    /// can never collide silently.
    @discardableResult
    func register<M: NotchDeckModule>(_ type: M.Type) throws -> ModuleDescriptor {
        let descriptor = M.descriptor
        guard index[descriptor.identifier] == nil else {
            throw ModuleRegistryError.duplicateIdentifier(descriptor.identifier)
        }
        modules.append(AnyNotchDeckModule(M.init()))
        index[descriptor.identifier] = modules.count - 1
        if !descriptor.defaultEnabled { disabled.insert(descriptor.identifier) }
        return descriptor
    }

    /// Map an old identifier onto a current one (future migrations).
    func addAlias(from old: String, to current: String) { aliases[old] = current }

    func module(identifier: String) -> AnyNotchDeckModule? {
        let id = aliases[identifier] ?? identifier
        guard let pos = index[id] else { return nil }
        return modules[pos]
    }

    func descriptor(identifier: String) -> ModuleDescriptor? {
        module(identifier: identifier)?.descriptor
    }

    var descriptors: [ModuleDescriptor] { modules.map(\.descriptor) }

    // MARK: Enabled state

    func isEnabled(_ identifier: String) -> Bool {
        guard let d = descriptor(identifier: identifier) else { return false }
        return !disabled.contains(d.identifier)
    }
    func setEnabled(_ enabled: Bool, identifier: String) {
        guard let d = descriptor(identifier: identifier) else { return }
        if enabled { disabled.remove(d.identifier) } else { disabled.insert(d.identifier) }
    }

    /// Enabled modules in registration order.
    var enabledModules: [AnyNotchDeckModule] {
        modules.filter { !disabled.contains($0.descriptor.identifier) }
    }

    /// Deterministic, stable ordering by identifier (for Settings lists).
    var sortedByIdentifier: [AnyNotchDeckModule] {
        modules.sorted { $0.descriptor.identifier < $1.descriptor.identifier }
    }

    /// Modules exposing a given surface, in registration order.
    func modules(for surface: ModuleSurface) -> [AnyNotchDeckModule] {
        modules.filter { $0.descriptor.surfaces.contains(surface) }
    }
}

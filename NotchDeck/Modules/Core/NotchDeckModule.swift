import SwiftUI

// MARK: - Community module architecture (source-integrated)
//
// This is the extensible foundation community contributors target through
// reviewed pull requests. Modules are COMPILED INTO NotchDeck — there is no
// runtime loading of arbitrary unsigned bundles / dylibs / downloaded code in
// this iteration (see docs/modules and the roadmap in SECURITY.md).
//
// It lives ALONGSIDE the existing built-in `NotchModule` widgets; existing
// features are unchanged. One example module (Modules/Examples) proves the
// architecture end to end.

/// A sensitive capability a module must DECLARE to be granted access to the
/// corresponding service. A module never silently gains access to everything.
enum ModuleCapability: String, CaseIterable, Codable, Equatable, Identifiable {
    case camera
    case screenRecording
    case selectedFolderAccess
    case downloadsAccess
    case terminalSessionEvents
    case agentApprovalEvents
    case mediaControl
    case notifications
    case backgroundExecution
    case terminalAutomation
    var id: String { rawValue }

    /// Every listed capability is sensitive and must be reviewed before merge.
    var isSensitive: Bool { true }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .screenRecording: return "Screen Recording"
        case .selectedFolderAccess: return "Selected-folder access"
        case .downloadsAccess: return "Downloads access"
        case .terminalSessionEvents: return "Terminal session events"
        case .agentApprovalEvents: return "Agent approval events"
        case .mediaControl: return "Media control"
        case .notifications: return "Notifications"
        case .backgroundExecution: return "Background execution"
        case .terminalAutomation: return "Terminal Automation"
        }
    }
}

/// Where a module wants to present itself. A module renders only for the
/// surfaces it declares.
enum ModuleSurface: String, CaseIterable, Codable, Equatable, Identifiable {
    case homeCard
    case expandedTab
    case compactLiveActivity
    case settingsSection
    case backgroundService
    /// A top-level workspace shown beside Utilities (currently only Agents).
    /// Never a Home card or a Utilities tab.
    case workspace
    /// The secondary "More" utility surface. Community modules ALWAYS render here
    /// and NEVER on Home (see `ModuleSurfaceRouting`).
    case more
    var id: String { rawValue }
}

/// High-level module category (independent of the built-in `ModuleCategory`).
enum ModuleCategoryKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case productivity
    case files
    case media
    case developerTools
    case system
    case example
    var id: String { rawValue }
}

/// Stable, declarative metadata for a module. Everything Settings and the
/// registry need — no view construction required to read it.
struct ModuleDescriptor: Equatable {
    /// Reverse-DNS-style unique identifier, e.g. "com.notchdeck.example.uptime".
    let identifier: String
    let displayName: String
    let summary: String
    /// Semantic version ("1.0.0").
    let version: String
    let author: String
    let category: ModuleCategoryKind
    /// SF Symbol name (built-in modules ship their own assets; community modules
    /// should prefer SF Symbols).
    let iconSystemName: String
    let defaultEnabled: Bool
    let surfaces: Set<ModuleSurface>
    let capabilities: Set<ModuleCapability>
    let hasSettings: Bool

    init(identifier: String, displayName: String, summary: String, version: String,
         author: String, category: ModuleCategoryKind, iconSystemName: String,
         defaultEnabled: Bool, surfaces: Set<ModuleSurface>,
         capabilities: Set<ModuleCapability> = [], hasSettings: Bool = false) {
        self.identifier = identifier
        self.displayName = displayName
        self.summary = summary
        self.version = version
        self.author = author
        self.category = category
        self.iconSystemName = iconSystemName
        self.defaultEnabled = defaultEnabled
        self.surfaces = surfaces
        self.capabilities = capabilities
        self.hasSettings = hasSettings
    }
}

/// Capability-gated access handed to a module at render/run time. A module can
/// only observe the capabilities it declared in its descriptor — the context is
/// the ONLY channel through which services are exposed. Raw approval sockets,
/// unrestricted shell execution and arbitrary filesystem access are never
/// exposed here.
struct ModuleContext {
    let granted: Set<ModuleCapability>

    /// True only when the module declared this capability (and review granted it).
    func has(_ capability: ModuleCapability) -> Bool { granted.contains(capability) }

    /// Convenience: the granted subset filtered to sensitive capabilities.
    var sensitiveCapabilities: Set<ModuleCapability> { granted.filter(\.isSensitive) }
}

/// The protocol community modules implement. Views are optional per surface so a
/// background-only or Home-only module need not implement the rest.
@MainActor
protocol NotchDeckModule {
    /// Stable metadata (must be a pure value — no view construction).
    static var descriptor: ModuleDescriptor { get }

    init()

    /// Home card view (only called when `.homeCard` is a declared surface).
    func homeCard(context: ModuleContext) -> AnyView?
    /// More dashboard card (only called when `.more` is declared).
    func moreCard(context: ModuleContext) -> AnyView?
    /// Expanded dedicated tab view (only for `.expandedTab`).
    func expandedView(context: ModuleContext) -> AnyView?
    /// Settings section (only when `hasSettings` / `.settingsSection`).
    func settingsView(context: ModuleContext) -> AnyView?
}

/// Sensible defaults so modules implement only what they need.
extension NotchDeckModule {
    func homeCard(context: ModuleContext) -> AnyView? { nil }
    func moreCard(context: ModuleContext) -> AnyView? { nil }
    func expandedView(context: ModuleContext) -> AnyView? { nil }
    func settingsView(context: ModuleContext) -> AnyView? { nil }
}

/// Type-erased module so the registry can store heterogeneous modules without
/// unsafe casts.
@MainActor
struct AnyNotchDeckModule {
    let descriptor: ModuleDescriptor
    private let _homeCard: (ModuleContext) -> AnyView?
    private let _moreCard: (ModuleContext) -> AnyView?
    private let _expandedView: (ModuleContext) -> AnyView?
    private let _settingsView: (ModuleContext) -> AnyView?

    init<M: NotchDeckModule>(_ module: M) {
        self.descriptor = M.descriptor
        self._homeCard = module.homeCard
        self._moreCard = module.moreCard
        self._expandedView = module.expandedView
        self._settingsView = module.settingsView
    }

    /// A context carrying exactly the module's declared capabilities.
    var context: ModuleContext { ModuleContext(granted: descriptor.capabilities) }

    func homeCard() -> AnyView? { _homeCard(context) }
    func moreCard() -> AnyView? { _moreCard(context) }
    func expandedView() -> AnyView? { _expandedView(context) }
    func settingsView() -> AnyView? { _settingsView(context) }
}

import SwiftUI

/// Dashboard card size a module can be shown at on the Utilities Home.
enum ModuleDashboardSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Grid column span (Home uses a 4-column flexible grid).
    var columnSpan: Int {
        switch self { case .small: return 1; case .medium: return 2; case .large: return 4 }
    }
    /// Preferred card height.
    var height: CGFloat {
        switch self { case .small: return 96; case .medium: return 128; case .large: return 176 }
    }
}

/// Which Utilities tab a module belongs to by default (iteration 9 grouping).
enum ModuleGroup: String, Codable, CaseIterable, Identifiable {
    case home, focus, files, more
    var id: String { rawValue }
    var title: String { self == .more ? "More" : rawValue.capitalized }
    var icon: String {
        switch self { case .home: return "house"; case .focus: return "target"
                      case .files: return "folder"; case .more: return "square.grid.2x2" }
    }
}

/// Category a module belongs to, driving the Utilities tab it appears under.
enum ModuleCategory: String, Codable, CaseIterable, Identifiable {
    case productivity
    case media
    case files
    var id: String { rawValue }
    var title: String {
        switch self { case .productivity: return "Productivity"
                      case .media: return "Media"
                      case .files: return "Files" }
    }
    var icon: String {
        switch self { case .productivity: return "checklist"
                      case .media: return "play.rectangle"
                      case .files: return "folder" }
    }
}

/// Per-module compact live-activity visibility policy.
enum CompactVisibilityPolicy: String, Codable, CaseIterable, Identifiable {
    case never
    case whileActive
    case always
    var id: String { rawValue }
    var label: String {
        switch self { case .never: return "Never"
                      case .whileActive: return "While active"
                      case .always: return "Always" }
    }
}

/// A configurable NotchDeck module. Metadata is plain data; views are built on
/// demand. Views pull shared services from the SwiftUI environment, so modules
/// carry no dependencies and the registry/Home/live-activities stay data-driven
/// — adding a module never requires editing `UtilitiesFaceView` or
/// `CompactNotchView`.
protocol NotchModule {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }               // SF Symbol
    var isAvailable: Bool { get }
    var defaultEnabled: Bool { get }           // present in the module library
    var defaultHomeFavorite: Bool { get }      // shown on Home by default
    var defaultDashboardSize: ModuleDashboardSize { get }
    var supportedSizes: [ModuleDashboardSize] { get }
    var requiredPermission: AppPermission? { get }
    var defaultPriority: Int { get }           // lower = earlier
    var category: ModuleCategory { get }
    var defaultGroup: ModuleGroup { get }
    /// Responsive card dimensions (points). The Home solver never shrinks a card
    /// below its minimum; it moves overflow modules off Home instead.
    var minWidth: CGFloat { get }
    var preferredWidth: CGFloat { get }
    var minHeight: CGFloat { get }
    var preferredHeight: CGFloat { get }
    var defaultCompactVisibility: CompactVisibilityPolicy { get }

    /// Dashboard card at a given size (Home).
    @MainActor func makeDashboardCard(size: ModuleDashboardSize) -> AnyView
    /// Full focused view (Focus Mode).
    @MainActor func makeFocusView() -> AnyView
    /// Optional per-module settings pane.
    @MainActor func makeSettingsView() -> AnyView?

    // MARK: Widget dashboard (iteration 8)
    var supportedWidgetSizes: [DashboardWidgetSize] { get }
    var defaultWidgetSize: DashboardWidgetSize { get }
    var preferredStyle: DashboardWidgetStyle { get }
    /// Whether this widget can contribute a compact live activity.
    var canLiveActivity: Bool { get }
    /// Distinct-identity widget view at a supported size. Defaults to the
    /// dashboard card so unconverted modules still render.
    @MainActor func makeWidget(size: DashboardWidgetSize) -> AnyView
}

extension NotchModule {
    var isAvailable: Bool { true }
    var defaultHomeFavorite: Bool { true }
    var defaultDashboardSize: ModuleDashboardSize { .medium }
    var supportedSizes: [ModuleDashboardSize] { ModuleDashboardSize.allCases }
    var requiredPermission: AppPermission? { nil }
    var defaultPriority: Int { 100 }
    var category: ModuleCategory { .productivity }
    var defaultGroup: ModuleGroup { .more }
    var minWidth: CGFloat { 150 }
    var preferredWidth: CGFloat { 220 }
    var minHeight: CGFloat { 88 }
    var preferredHeight: CGFloat { defaultDashboardSize.height }
    var defaultCompactVisibility: CompactVisibilityPolicy { .whileActive }
    @MainActor func makeSettingsView() -> AnyView? { nil }

    // Widget defaults — map to the existing dashboard cards.
    var supportedWidgetSizes: [DashboardWidgetSize] { [.small, .medium, .wide, .large] }
    var defaultWidgetSize: DashboardWidgetSize { .medium }
    var preferredStyle: DashboardWidgetStyle { .tile }
    var canLiveActivity: Bool { false }
    @MainActor func makeWidget(size: DashboardWidgetSize) -> AnyView {
        makeDashboardCard(size: size.legacySize)
    }
}

extension DashboardWidgetSize {
    /// Map a widget size onto the legacy 3-size dashboard card API.
    var legacySize: ModuleDashboardSize {
        switch self {
        case .compact, .small: return .small
        case .medium, .wide: return .medium
        case .large: return .large
        }
    }
}

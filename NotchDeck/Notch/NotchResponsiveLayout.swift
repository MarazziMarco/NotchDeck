import AppKit

/// Semantic layout class derived from actual usable logical width — NEVER from a
/// commercial Mac model or hardcoded inch size.
enum NotchLayoutClass: String, Equatable {
    case compact
    case regular
    case spacious
}

/// Plain, synthetic-testable description of a display's geometry.
struct ScreenGeometry: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var notchWidth: CGFloat       // 0 on notch-less displays
    var notchHeight: CGFloat
    var backingScaleFactor: CGFloat
    var hasNotch: Bool { notchWidth > 0 && notchHeight > 0 }

    static func from(_ screen: NSScreen) -> ScreenGeometry {
        var notchW: CGFloat = 0
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = max(0, screen.frame.width - l.width - r.width)
        }
        return ScreenGeometry(frame: screen.frame,
                              visibleFrame: screen.visibleFrame,
                              notchWidth: notchW,
                              notchHeight: screen.safeAreaInsets.top,
                              backingScaleFactor: screen.backingScaleFactor)
    }
}

/// Per-tab width profile. Home is intentionally the widest; Focus stays narrow
/// even under a Wide preference; Files/More sit in between. Values are offsets
/// applied to the sub-linear base, with per-tab hard maxima (all still clamped
/// to `visibleFrame − 48` and ≥24 pt side margins).
enum UtilitiesWidthProfile: String, Equatable {
    case home, focus, files, more

    var hardMax: CGFloat {
        switch self { case .home: return 1120; case .files: return 1000
                      case .focus: return 900; case .more: return 1000 }
    }
    /// Base width offset added on top of the user width preference.
    func widthOffset(for pref: PanelWidthPreference) -> CGFloat {
        let base: CGFloat = { switch self { case .home: return 180; case .files: return 80
                                            case .focus: return -20; case .more: return 60 } }()
        // Wide nudges Home a little further toward its cap; Focus is left narrow.
        if pref == .wide && self == .home { return base + 40 }
        return base
    }
}

/// User width preference (Appearance ▸ Layout).
enum PanelWidthPreference: String, Codable, CaseIterable, Identifiable {
    case adaptive, compact, comfortable, wide
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Width offset (points) applied to the adaptive base. Larger screens use
    /// proportionally less width (sub-linear base), so preferences are offsets
    /// rather than raw fractions.
    var offset: CGFloat {
        switch self {
        case .compact: return -60
        case .adaptive: return 0
        case .comfortable: return 55
        case .wide: return 120
        }
    }
}

enum DashboardDensity: String, Codable, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TabLabelMode: String, Codable, CaseIterable, Identifiable {
    case automatic, iconsAndLabels, iconsOnly
    var id: String { rawValue }
    var label: String {
        switch self { case .automatic: return "Automatic"
                      case .iconsAndLabels: return "Icons & labels"
                      case .iconsOnly: return "Icons only" }
    }
}

struct AccessibilityLayoutPreferences: Equatable {
    var largeText: Bool = false
    var reduceMotion: Bool = false
}

/// Resolved responsive layout for the current display + preferences.
struct NotchResponsiveLayout: Equatable {
    var panelWidth: CGFloat
    var dashboardHeight: CGFloat
    var layoutClass: NotchLayoutClass
    var sideMargin: CGFloat
    var horizontalPadding: CGFloat
    var sideColumnWidth: CGFloat
    var maxHomeModules: Int
    var resolvedTabLabels: TabLabelMode
    var hasNotch: Bool
    var housingWidth: CGFloat
}

/// Computes responsive panel geometry purely from logical screen geometry and
/// user/accessibility preferences. Fully unit-testable with `ScreenGeometry`.
@MainActor
final class NotchResponsiveLayoutService: ObservableObject {

    /// Preferred content height (points) for the active Utilities tab. Views set
    /// this per tab; the panel controller resizes to it so Home doesn't leave a
    /// blank lower half. Animated between tab changes.
    @Published var utilitiesContentHeight: CGFloat = 268

    /// Active Utilities tab width profile (Home is widest). Set by the tab view.
    @Published var utilitiesTab: UtilitiesWidthProfile = .home

    /// Latest resolved layout, published so views adapt on display / preference
    /// changes. Seeded with a reasonable regular default.
    @Published var current: NotchResponsiveLayout = NotchResponsiveLayout(
        panelWidth: 760, dashboardHeight: 320, layoutClass: .regular,
        sideMargin: 22, horizontalPadding: 12, sideColumnWidth: 220,
        maxHomeModules: 4, resolvedTabLabels: .iconsAndLabels,
        hasNotch: true, housingWidth: 200)

    nonisolated static let hardMinWidth: CGFloat = 620
    nonisolated static let hardMaxWidth: CGFloat = 980
    nonisolated static let hardMaxHeight: CGFloat = 400

    struct Preferences: Equatable {
        var width: PanelWidthPreference = .adaptive
        var density: DashboardDensity = .comfortable
        var tabLabels: TabLabelMode = .automatic
        /// nil = automatic (depends on layout class).
        var maxHomeModules: Int? = nil
    }

    nonisolated static func compute(screen: ScreenGeometry,
                                    face: NotchFace,
                                    prefs: Preferences,
                                    accessibility: AccessibilityLayoutPreferences,
                                    tab: UtilitiesWidthProfile? = nil) -> NotchResponsiveLayout {
        let available = screen.visibleFrame.width
        let baseMargin: CGFloat = 24
        let maxAllowed = max(0, available - baseMargin * 2)

        // Sub-linear base so larger displays use proportionally less width and
        // never resemble a full app window.
        let base = 0.38 * available + 215

        // Per-tab width profile (Home widest). Tab-less callers keep the prior
        // behaviour (utilities +55 / agents +25, hard max 980) so older layouts
        // and tests are unaffected.
        let profileOffset: CGFloat
        let profileMax: CGFloat
        if face == .utilities, let tab {
            profileOffset = tab.widthOffset(for: prefs.width)
            profileMax = tab.hardMax
        } else {
            profileOffset = face == .utilities ? 55 : 25
            profileMax = hardMaxWidth
        }
        let preferred = base + prefs.width.offset + profileOffset

        // Clamp: never exceed what fits on screen; respect hard bounds. On very
        // small screens fall below the soft minimum rather than crossing edges.
        let softMin = min(hardMinWidth, maxAllowed)
        let upper = min(maxAllowed, profileMax)
        var panelWidth = min(max(preferred, softMin), max(softMin, upper))
        panelWidth = panelWidth.rounded()

        // Layout class from the resulting usable width.
        let layoutClass: NotchLayoutClass
        if panelWidth < 730 { layoutClass = .compact }
        else if panelWidth < 850 { layoutClass = .regular }
        else { layoutClass = .spacious }

        // Height (wide + short), capped. Accessibility large text gets a bit more.
        var height: CGFloat
        switch layoutClass {
        case .compact: height = 300
        case .regular: height = 320
        case .spacious: height = 336
        }
        if accessibility.largeText { height = min(hardMaxHeight, height + 24) }
        height = min(height, hardMaxHeight, max(200, screen.visibleFrame.height - 40))

        let sideMargin: CGFloat = layoutClass == .compact ? 12 : (layoutClass == .regular ? 22 : 30)
        let horizontalPadding: CGFloat = layoutClass == .compact ? 10 : (layoutClass == .regular ? 12 : 14)

        // Responsive side column — NOT a fixed 236pt.
        let sideColumnWidth = min(max(panelWidth * 0.28, 176), 260).rounded()

        // Max Home modules.
        let autoMax = layoutClass == .compact ? 3 : 4
        let maxHome = prefs.maxHomeModules ?? autoMax

        // Resolve tab labels.
        let resolvedTabs: TabLabelMode
        switch prefs.tabLabels {
        case .automatic: resolvedTabs = layoutClass == .compact ? .iconsOnly : .iconsAndLabels
        default: resolvedTabs = prefs.tabLabels
        }

        return NotchResponsiveLayout(
            panelWidth: panelWidth,
            dashboardHeight: height,
            layoutClass: layoutClass,
            sideMargin: sideMargin,
            horizontalPadding: horizontalPadding,
            sideColumnWidth: sideColumnWidth,
            maxHomeModules: maxHome,
            resolvedTabLabels: resolvedTabs,
            hasNotch: screen.hasNotch,
            housingWidth: screen.hasNotch ? screen.notchWidth : 0)
    }

    /// Panel frame in global coordinates for a given expanded content height.
    /// Centered horizontally; pinned to the top of the notch on notched displays
    /// or just below the menu bar on external displays; always kept inside
    /// `visibleFrame` horizontally.
    nonisolated static func expandedPanelFrame(screen: ScreenGeometry,
                                               layout: NotchResponsiveLayout,
                                               compactHeight: CGFloat) -> CGRect {
        let width = layout.panelWidth
        let height = layout.dashboardHeight + compactHeight
        let originX = (screen.frame.midX - width / 2)
            .clamped(min: screen.visibleFrame.minX + 4,
                     max: screen.visibleFrame.maxX - width - 4)
        // Notched: hug the physical top. External: sit below the menu bar.
        let topY = screen.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY
        let originY = topY - height
        return CGRect(x: originX.rounded(), y: originY.rounded(),
                      width: width.rounded(), height: height.rounded())
    }
}

extension CGFloat {
    func clamped(min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), Swift.max(lo, hi))
    }
}

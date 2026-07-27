import Foundation
import CoreGraphics

/// How the Home tab is composed. Editorial is the polished default; grid falls
/// back to the generic `GridSolver`; minimal shows a reduced set.
enum HomeCompositionStyle: String, Codable, CaseIterable, Identifiable {
    case editorial
    case grid
    case minimal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Semantic zone width used in Customize mode (no free pixel resizing).
enum EditorialZoneWidth: String, Codable, CaseIterable, Identifiable {
    case narrow, standard, prominent
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Size selector label used in the customization sheet.
    var sizeLabel: String { switch self { case .narrow: return "Small"; case .standard: return "Medium"; case .prominent: return "Large" } }
    var multiplier: CGFloat { switch self { case .narrow: return 0.75; case .standard: return 1.0; case .prominent: return 1.35 } }
}

extension EditorialZoneWidth {
    init(_ size: ModuleDashboardSize) {
        switch size {
        case .small: self = .narrow
        case .medium: self = .standard
        case .large: self = .prominent
        }
    }

    var dashboardSize: ModuleDashboardSize {
        switch self {
        case .narrow: return .small
        case .standard: return .medium
        case .prominent: return .large
        }
    }
}

/// Home layout preset (density). Balanced is the default. Each preset yields a
/// distinct set of geometry tokens actually consumed by production Home.
enum HomeLayoutPreset: String, Codable, CaseIterable, Identifiable {
    case compact, balanced, spacious
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Explicit, visibly-distinct geometry tokens.
    var tokens: HomeGeometryTokens {
        switch self {
        case .compact:  return HomeGeometryTokens(leadingInset: 14, trailingInset: 16, moduleGap: 12,
                                                  internalPadding: 6, bottomBreathing: 16, heightDelta: -22)
        case .balanced: return HomeGeometryTokens(leadingInset: 22, trailingInset: 24, moduleGap: 20,
                                                  internalPadding: 10, bottomBreathing: 26, heightDelta: 0)
        case .spacious: return HomeGeometryTokens(leadingInset: 30, trailingInset: 34, moduleGap: 28,
                                                  internalPadding: 14, bottomBreathing: 36, heightDelta: 26)
        }
    }
    var heightDelta: CGFloat { tokens.heightDelta }
}

/// Geometry tokens driving Home edge insets, gaps, padding and height.
struct HomeGeometryTokens: Equatable {
    var leadingInset: CGFloat
    var trailingInset: CGFloat
    var moduleGap: CGFloat
    var internalPadding: CGFloat
    var bottomBreathing: CGFloat
    var heightDelta: CGFloat
}

/// A resolved editorial zone with a concrete pixel frame in the content area.
struct EditorialZone: Identifiable, Equatable {
    var id: String { moduleID }
    var moduleID: String
    var frame: CGRect
}

struct EditorialPage: Equatable {
    var zones: [EditorialZone]
    var pageCount: Int
}

/// Pure, deterministic editorial layout — one full-height row on regular/spacious
/// and two pages on compact. Enforces per-module minimum widths and keeps Mirror
/// the rightmost element on page 0 of the single-row layouts.
enum EditorialHomeLayout {
    /// Default module order. Mirror is intentionally last (rightmost).
    static let defaultOrder = ["quickNote", "nowPlaying", "fileShelf", "mirror"]

    static let defaultRatios: [String: CGFloat] = [
        "quickNote": 0.32, "nowPlaying": 0.22, "fileShelf": 0.27, "mirror": 0.19,
    ]

    /// Ratios adapt slightly by layout class.
    static func ratios(for layoutClass: NotchLayoutClass) -> [String: CGFloat] {
        switch layoutClass {
        case .regular: return ["quickNote": 0.31, "nowPlaying": 0.23, "fileShelf": 0.27, "mirror": 0.19]
        default: return defaultRatios
        }
    }

    static let minWidths: [String: CGFloat] = [
        "quickNote": 150, "nowPlaying": 150, "fileShelf": 130, "mirror": 120,
    ]

    /// Whether the four zones fit one readable row at `contentWidth`.
    static func fitsOneRow(order: [String], ratios: [String: CGFloat],
                           minWidths: [String: CGFloat], contentWidth: CGFloat,
                           dividerWidth: CGFloat = 1, spacing: CGFloat = 12) -> Bool {
        let n = order.count
        guard n > 0 else { return true }
        let available = max(0, contentWidth - CGFloat(n - 1) * (spacing + dividerWidth))
        let total = order.reduce(0) { $0 + (ratios[$1] ?? 0.25) }
        for id in order {
            let w = available * (ratios[id] ?? 0.25) / max(0.0001, total)
            if w < (minWidths[id] ?? 100) - 0.5 { return false }
        }
        return true
    }

    /// Whether Home should page instead of one row (compact always; regular when
    /// minimum widths can't be met; spacious never).
    static func requiresPaging(order: [String], ratios: [String: CGFloat],
                               minWidths: [String: CGFloat], contentWidth: CGFloat,
                               layoutClass: NotchLayoutClass) -> Bool {
        switch layoutClass {
        case .compact: return true
        case .spacious: return false
        case .regular: return !fitsOneRow(order: order, ratios: ratios, minWidths: minWidths, contentWidth: contentWidth)
        }
    }

    /// Split modules into pages. `paged` forces the two-page split even on a
    /// regular layout that can't fit one readable row.
    static func pages(order: [String], layoutClass: NotchLayoutClass, paged: Bool = false) -> [[String]] {
        guard layoutClass == .compact || paged else { return [order] }
        var result: [[String]] = []
        var i = 0
        while i < order.count {
            result.append(Array(order[i..<min(i + 2, order.count)]))
            i += 2
        }
        return result.isEmpty ? [order] : result
    }

    static func layout(order: [String] = defaultOrder,
                       ratios: [String: CGFloat] = defaultRatios,
                       minWidths: [String: CGFloat] = minWidths,
                       contentSize: CGSize,
                       layoutClass: NotchLayoutClass,
                       page: Int,
                       paged: Bool = false,
                       dividerWidth: CGFloat = 1,
                       spacing: CGFloat = 12) -> EditorialPage {
        let allPages = pages(order: order, layoutClass: layoutClass, paged: paged)
        let idx = max(0, min(page, allPages.count - 1))
        let pageModules = allPages[idx]
        let n = pageModules.count
        guard n > 0 else { return EditorialPage(zones: [], pageCount: allPages.count) }

        let gaps = CGFloat(max(0, n - 1)) * (spacing + dividerWidth)
        let available = max(0, contentSize.width - gaps)

        // Normalized preferred widths over this page's modules.
        let totalRatio = pageModules.reduce(0) { $0 + (ratios[$1] ?? 0.25) }
        var widths = pageModules.map { (available * (ratios[$0] ?? 0.25) / max(0.0001, totalRatio)) }

        // Enforce minimums, redistributing the deficit from the widest zones.
        for i in pageModules.indices {
            let minW = minWidths[pageModules[i]] ?? 100
            if widths[i] < minW {
                let deficit = minW - widths[i]
                widths[i] = minW
                // take from the largest other zone
                if let j = widths.enumerated().filter({ $0.offset != i })
                    .max(by: { $0.element < $1.element })?.offset {
                    widths[j] = max(minWidths[pageModules[j]] ?? 100, widths[j] - deficit)
                }
            }
        }

        var zones: [EditorialZone] = []
        var x: CGFloat = 0
        for i in pageModules.indices {
            let w = widths[i]
            zones.append(EditorialZone(moduleID: pageModules[i],
                                       frame: CGRect(x: x, y: 0, width: w, height: contentSize.height)))
            x += w + spacing + dividerWidth
        }
        return EditorialPage(zones: zones, pageCount: allPages.count)
    }

    /// Preferred content height (points) per Utilities tab.
    static func contentHeight(tab: String, layoutClass: NotchLayoutClass) -> CGFloat {
        switch tab {
        // Includes bottom breathing room so the tallest module never touches the edge.
        case "home": return layoutClass == .compact ? 300 : 330
        case "focus": return 300
        case "files": return 300
        default: return 240
        }
    }
}

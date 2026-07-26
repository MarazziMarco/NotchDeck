import Foundation
import CoreGraphics

/// Widget size — maps to a fixed span of grid cells (width × height), scaled by
/// the columns of the active layout class.
enum DashboardWidgetSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case small
    case medium
    case wide
    case large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Column × row cell span.
    var cells: (w: Int, h: Int) {
        switch self {
        case .compact: return (2, 1)
        case .small:   return (2, 2)
        case .medium:  return (3, 2)
        case .wide:    return (4, 2)
        case .large:   return (4, 3)
        }
    }
    var colSpan: Int { cells.w }
    var rowSpan: Int { cells.h }
}

/// Preferred silhouette / composition for a widget. `automatic` lets the module
/// pick; the others give distinct visual identities.
enum DashboardWidgetStyle: String, Codable, CaseIterable, Identifiable {
    case automatic
    case circular    // Mirror
    case capsule     // battery / downloads
    case tile        // generic rounded tile
    case tray        // File Shelf
    case sheet       // Clipboard (layered paper)
    case custom      // module draws its own silhouette
    var id: String { rawValue }
}

/// A widget's placement on Home. Persisted per layout class — never absolute
/// pixels, only grid intent (order + preferred cell + size + visibility).
struct DashboardWidgetPlacement: Identifiable, Codable, Equatable {
    var id: String                // == moduleID (one widget per module on Home)
    var moduleID: String
    var order: Int
    var size: DashboardWidgetSize
    var preferredColumn: Int?
    var preferredRow: Int?
    var page: Int
    var isVisible: Bool

    init(moduleID: String, order: Int, size: DashboardWidgetSize,
         preferredColumn: Int? = nil, preferredRow: Int? = nil,
         page: Int = 0, isVisible: Bool = true) {
        self.id = moduleID
        self.moduleID = moduleID
        self.order = order
        self.size = size
        self.preferredColumn = preferredColumn
        self.preferredRow = preferredRow
        self.page = page
        self.isVisible = isVisible
    }
}

/// Columns per semantic layout class. Logical layout units, not visible lines.
enum DashboardGrid {
    static func columns(for layoutClass: NotchLayoutClass) -> Int {
        switch layoutClass {
        case .compact: return 6
        case .regular: return 8
        case .spacious: return 10
        }
    }
    /// Max rows visible before overflowing to another page (keeps the notch short).
    static let maxRowsPerPage = 5
}

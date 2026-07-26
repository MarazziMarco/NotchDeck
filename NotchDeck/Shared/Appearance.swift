import SwiftUI

/// Panel background darkness. Accent color always comes from widgets, never the
/// base. Default is Deep Black.
enum BackgroundIntensity: String, Codable, CaseIterable, Identifiable {
    case standard
    case deepBlack
    case maxContrast
    var id: String { rawValue }
    var label: String {
        switch self { case .standard: return "Standard"
                      case .deepBlack: return "Deep Black"
                      case .maxContrast: return "Max Contrast" }
    }
    /// White level of the surface fill.
    var surfaceWhite: Double {
        switch self { case .standard: return 0.055; case .deepBlack: return 0.018; case .maxContrast: return 0.0 }
    }
    /// Opacity of the surface over the material (higher = less grey haze).
    /// Deep Black is fully opaque so the rounded corners read pure black with no
    /// grey material bleed; Standard keeps a slight translucency by choice.
    var surfaceOpacity: Double {
        switch self { case .standard: return 0.90; case .deepBlack: return 1.0; case .maxContrast: return 1.0 }
    }
    /// Whether to draw the translucent grey material behind the fill. ONLY
    /// Standard uses it (it is translucent by design). Deep Black and Max
    /// Contrast render a pure opaque near-black surface so the rounded lower
    /// corners never show a grey material fringe.
    var usesMaterial: Bool { self == .standard }
    var surfaceColor: Color { Color(white: surfaceWhite) }
    /// True when the base is fully opaque near-black — corners guaranteed black.
    var hasOpaqueBlackCorners: Bool { self != .standard }
}

/// Mirror preview orientation. Default is a true mirror (horizontally flipped,
/// like a bathroom mirror).
enum MirrorOrientation: String, Codable, CaseIterable, Identifiable {
    case mirrored
    case trueView
    var id: String { rawValue }
    var label: String {
        switch self { case .mirrored: return "Mirrored"
                      case .trueView: return "Camera true view" }
    }
    /// Whether the preview connection should be horizontally mirrored.
    var isMirrored: Bool { self == .mirrored }
}

/// Post-it colours for the Home Quick Note.
enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case yellow, pink, green, blue
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Warm, muted paper tone (kept premium, not neon).
    var paper: Color {
        switch self {
        case .yellow: return Color(red: 0.86, green: 0.78, blue: 0.42)
        case .pink:   return Color(red: 0.82, green: 0.62, blue: 0.66)
        case .green:  return Color(red: 0.62, green: 0.76, blue: 0.60)
        case .blue:   return Color(red: 0.58, green: 0.70, blue: 0.82)
        }
    }
    var ink: Color { Color(red: 0.12, green: 0.10, blue: 0.05) }
}

/// Paper texture strength for the note.
enum PaperStyleIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle, medium, strong
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var shadow: CGFloat { switch self { case .subtle: return 3; case .medium: return 6; case .strong: return 10 } }
    var showsFold: Bool { self != .subtle }
}

/// Note font size on Home.
enum NoteFontSize: String, Codable, CaseIterable, Identifiable {
    case compact, standard, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var points: CGFloat { switch self { case .compact: return 11; case .standard: return 13; case .large: return 16 } }
}

/// Mirror preview crop / zoom (safe aspect-fill cropping, not hardware zoom).
enum MirrorCropLevel: String, Codable, CaseIterable, Identifiable {
    case natural, close, closer
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scale: CGFloat { switch self { case .natural: return 1.0; case .close: return 1.35; case .closer: return 1.55 } }
}

/// How the Files right column splits vertically between Downloads and Screen.
enum FilesRightSplit: String, Codable, CaseIterable, Identifiable {
    case balanced, downloadsProminent, screenProminent
    var id: String { rawValue }
    var label: String {
        switch self { case .balanced: return "Balanced"
                      case .downloadsProminent: return "Downloads prominent"
                      case .screenProminent: return "Screen prominent" }
    }
    /// Fraction of the right column's height given to Downloads (top).
    var downloadsFraction: CGFloat {
        switch self { case .balanced: return 0.55; case .downloadsProminent: return 0.62; case .screenProminent: return 0.45 }
    }
}

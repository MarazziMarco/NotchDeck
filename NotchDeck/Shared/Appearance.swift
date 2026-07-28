import SwiftUI
import AppKit

/// Persistable sRGB paper colour shared by every Quick Note presentation.
struct NotePaperColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init?(color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        srgb.getRed(&red, green: &green, blue: &blue, alpha: &opacity)
        self.init(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(opacity)
        )
    }

    var clamped: NotePaperColor {
        NotePaperColor(
            red: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            opacity: opacity.clamped(to: 0...1)
        )
    }

    var color: Color {
        let value = clamped
        return Color(
            .sRGB,
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.opacity
        )
    }

    /// Picks the ink with the better WCAG contrast against the paper.
    var usesLightInk: Bool {
        relativeLuminance < 0.179
    }

    var inkColor: Color {
        usesLightInk
            ? Color(red: 0.98, green: 0.98, blue: 0.96)
            : Color(red: 0.12, green: 0.10, blue: 0.05)
    }

    private var relativeLuminance: Double {
        let value = clamped
        return 0.2126 * Self.linear(value.red)
            + 0.7152 * Self.linear(value.green)
            + 0.0722 * Self.linear(value.blue)
    }

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

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
    /// The one authoritative notch surface is always opaque. Intensity changes
    /// only its near-black white level, never host/material visibility.
    var surfaceOpacity: Double {
        1.0
    }
    /// Materials are intentionally excluded from the outer notch surface because
    /// they create a wallpaper-dependent grey layer at the rounded edge.
    var usesMaterial: Bool { false }
    var surfaceColor: Color { Color(white: surfaceWhite) }
    var hasOpaqueBlackCorners: Bool { true }
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
    case yellow, pink, green, blue, orange, purple
    var id: String { rawValue }
    var label: String {
        switch self {
        case .yellow: return "Classic Yellow"
        default: return rawValue.capitalized
        }
    }
    var paperComponents: NotePaperColor {
        switch self {
        case .yellow: return NotePaperColor(red: 1.00, green: 0.898, blue: 0.42)
        case .pink:   return NotePaperColor(red: 1.00, green: 0.62, blue: 0.71)
        case .green:  return NotePaperColor(red: 0.67, green: 0.90, blue: 0.56)
        case .blue:   return NotePaperColor(red: 0.57, green: 0.79, blue: 1.00)
        case .orange: return NotePaperColor(red: 1.00, green: 0.71, blue: 0.37)
        case .purple: return NotePaperColor(red: 0.78, green: 0.64, blue: 1.00)
        }
    }
    var paper: Color { paperComponents.color }
    var ink: Color { paperComponents.inkColor }
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

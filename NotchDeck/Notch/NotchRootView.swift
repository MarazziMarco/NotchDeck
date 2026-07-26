import SwiftUI

/// Top-level content of the panel. Renders the compact strip or the expanded
/// surface, with a shape that reads as a natural extension of the notch.
struct NotchRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var diagnostics: NotchDiagnostics
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var notchLayout: NotchLayoutInfo

    /// One authoritative radius per presentation: expanded, compact Focus (a
    /// shorter capsule → smaller radius), or the default compact/idle radius.
    private var cornerRadius: CGFloat {
        if appState.isExpanded { return DesignTokens.Metrics.expandedCornerRadius }
        if notchLayout.compactFocus { return CompactFocusGeometry.cornerRadius }
        return DesignTokens.Metrics.compactCornerRadius
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The panel base (keeps its own soft shadow — NOT clipped at root).
            NotchBackground(expanded: appState.isExpanded,
                            intensity: settings.settings.backgroundIntensity,
                            compactRadius: cornerRadius)
            // Content is clipped to the SAME shape/radius as the base, so no
            // square widget corner or grey backing can peek past the rounded
            // bottom corners.
            ZStack(alignment: .top) {
                if appState.isExpanded {
                    ExpandedNotchView()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    CompactNotchView()
                        .transition(.opacity)
                }
                if diagnostics.enabled && appState.isExpanded {
                    DiagnosticsOverlay(d: diagnostics)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(BottomRoundedShape(radius: cornerRadius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(DesignTokens.Motion.expand(reduceMotion: appState.reduceMotion),
                   value: appState.presentation)
    }
}

/// The panel's dark surface. Near-solid black when compact so it blends with the
/// physical notch; a deep charcoal-black surface with a thin dark material base,
/// a faint hairline and a soft shadow when expanded — no milky-grey glass.
struct NotchBackground: View {
    let expanded: Bool
    var intensity: BackgroundIntensity = .deepBlack
    /// Compact/idle corner radius (compact Focus uses a smaller one). Expanded
    /// ignores this.
    var compactRadius: CGFloat = DesignTokens.Metrics.compactCornerRadius

    var body: some View {
        let radius = expanded ? DesignTokens.Metrics.expandedCornerRadius : compactRadius
        ZStack {
            if expanded {
                // Optional dark material for depth (off at Max Contrast), then a
                // near-opaque near-black fill so it never reads as grey glass.
                if intensity.usesMaterial {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                }
                intensity.surfaceColor.opacity(intensity.surfaceOpacity)
                // Very subtle top-edge sheen for a premium, non-flat look.
                LinearGradient(
                    colors: [Color.white.opacity(0.035), Color.clear],
                    startPoint: .top, endPoint: .center)
            } else {
                Color.black   // compact stays as black as possible
            }
        }
        .clipShape(BottomRoundedShape(radius: radius))
        .overlay(
            // Border ONLY for the expanded panel. Compact / physical-idle draw NO
            // hairline (it read as a grey edge around the notch).
            BottomRoundedShape(radius: radius)
                .strokeBorder(DesignTokens.Palette.hairline,
                              lineWidth: expanded ? CompactChrome.expandedBorderWidth : CompactChrome.compactBorderWidth)
        )
        // Shadow ONLY for the expanded panel. Compact / physical-idle have NO
        // shadow so there is no grey lower edge / rectangular shadow bound.
        .shadow(color: .black.opacity(expanded ? 0.45 : 0),
                radius: expanded ? CompactChrome.expandedShadowRadius : CompactChrome.compactShadowRadius,
                y: expanded ? 10 : 0)
    }
}

/// Border / shadow chrome. The compact + physical-idle states use NONE (no grey
/// hairline, no shadow); only the expanded panel is decorated.
enum CompactChrome {
    static let compactBorderWidth: CGFloat = 0
    static let compactShadowRadius: CGFloat = 0
    static let expandedBorderWidth: CGFloat = 0.8
    static let expandedShadowRadius: CGFloat = 22
}

/// A rectangle with only its bottom corners rounded — the top meets the screen
/// edge flush, like the physical notch.
struct BottomRoundedShape: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self; copy.inset += amount; return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = min(self.radius, r.height, r.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY),
                          control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius),
                          control: CGPoint(x: r.minX, y: r.maxY))
        path.closeSubpath()
        return path
    }
}

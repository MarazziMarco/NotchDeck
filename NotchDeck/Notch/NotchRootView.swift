import SwiftUI

/// Top-level content of the panel. Renders the compact strip or the expanded
/// surface, with a shape that reads as a natural extension of the notch.
struct NotchRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var diagnostics: NotchDiagnostics
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var notchLayout: NotchLayoutInfo

    private var surface: NotchSurfaceDescriptor {
        NotchSurfaceTransitionPolicy.descriptor(
            presentation: appState.presentation,
            compactFocus: notchLayout.compactFocus,
            intensity: settings.settings.backgroundIntensity,
            reduceMotion: appState.reduceMotion
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The host stays transparent. This is the single persistent visible
            // surface through compact ↔ expanded frame changes.
            NotchSurface(descriptor: surface)

            ZStack(alignment: .top) {
                if CompactNotchPresentationPolicy.showsExpanded(in: appState.presentation) {
                    ExpandedNotchView()
                        .transition(.identity)
                } else {
                    CompactNotchView()
                        .transition(.identity)
                }
                if diagnostics.enabled && appState.isExpanded {
                    DiagnosticsOverlay(d: diagnostics)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // One shared clip rasterizes both the authoritative fill and content at
        // the exact same lower-corner boundary, avoiding Retina edge seams.
        .clipShape(BottomRoundedShape(radius: surface.cornerRadius))
        .animation(DesignTokens.Motion.expand(reduceMotion: appState.reduceMotion),
                   value: appState.presentation)
    }
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

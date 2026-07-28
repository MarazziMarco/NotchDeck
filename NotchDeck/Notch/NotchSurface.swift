import SwiftUI

/// One source for the visible notch surface geometry. Panel dimensions and the
/// physical-notch exclusion remain owned by `NotchGeometryService`; this type
/// owns the shared clipping radius and the deliberately absent in-bounds chrome.
enum NotchSurfaceGeometry {
    static let outerPadding: CGFloat = 0
    static let borderWidth: CGFloat = 0

    // The visible surface fills the NSPanel bounds, so there is no transparent
    // margin in which a SwiftUI shadow could render as a real external shadow.
    // Keeping these values explicit prevents an in-bounds halo from returning.
    static let expandedShadowRadius: CGFloat = 0
    static let expandedShadowOpacity: Double = 0
    static let expandedShadowOffsetY: CGFloat = 0

    static func cornerRadius(
        presentation: NotchPresentationState,
        compactFocus: Bool
    ) -> CGFloat {
        if presentation == .expanded {
            return DesignTokens.Metrics.expandedCornerRadius
        }
        return compactFocus
            ? CompactFocusGeometry.cornerRadius
            : DesignTokens.Metrics.compactCornerRadius
    }
}

/// Pure description consumed directly by `NotchSurface`. It intentionally has
/// exactly one opaque fill and no material, border or secondary rounded layer.
struct NotchSurfaceDescriptor: Equatable {
    var surfaceWhite: Double
    var cornerRadius: CGFloat
    var isOpaque: Bool
    var usesMaterial: Bool
    var backgroundLayerCount: Int
    var outerPadding: CGFloat
    var borderWidth: CGFloat
    var shadowRadius: CGFloat
    var shadowOpacity: Double
    var shadowOffsetY: CGFloat

    static func resolve(
        presentation: NotchPresentationState,
        compactFocus: Bool,
        intensity: BackgroundIntensity
    ) -> Self {
        let expanded = presentation == .expanded
        return Self(
            surfaceWhite: expanded ? intensity.surfaceWhite : 0,
            cornerRadius: NotchSurfaceGeometry.cornerRadius(
                presentation: presentation,
                compactFocus: compactFocus
            ),
            isOpaque: true,
            usesMaterial: false,
            backgroundLayerCount: 1,
            outerPadding: NotchSurfaceGeometry.outerPadding,
            borderWidth: NotchSurfaceGeometry.borderWidth,
            shadowRadius: expanded ? NotchSurfaceGeometry.expandedShadowRadius : 0,
            shadowOpacity: expanded ? NotchSurfaceGeometry.expandedShadowOpacity : 0,
            shadowOffsetY: expanded ? NotchSurfaceGeometry.expandedShadowOffsetY : 0
        )
    }
}

/// Reduce Motion changes only transition timing. Both paths resolve the same
/// final, single-surface composition.
enum NotchSurfaceTransitionPolicy {
    static func descriptor(
        presentation: NotchPresentationState,
        compactFocus: Bool,
        intensity: BackgroundIntensity,
        reduceMotion: Bool
    ) -> NotchSurfaceDescriptor {
        NotchSurfaceDescriptor.resolve(
            presentation: presentation,
            compactFocus: compactFocus,
            intensity: intensity
        )
    }
}

/// The sole visible base for both compact and expanded states. The NSPanel and
/// NSHostingView remain transparent; this opaque near-black fill reaches the
/// shared root clip exactly, with no inset container behind it.
struct NotchSurface: View {
    let descriptor: NotchSurfaceDescriptor

    var body: some View {
        Color(white: descriptor.surfaceWhite)
            .accessibilityHidden(true)
    }
}

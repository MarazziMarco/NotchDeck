import CoreGraphics
import Combine

/// Always-available compact geometry so `CompactNotchView` can place content in
/// the visible wings beside the physical camera housing instead of centered
/// underneath it. Updated by `NotchPanelController` on every reposition.
@MainActor
final class NotchLayoutInfo: ObservableObject {
    @Published var hasNotch: Bool = false
    /// Width of the whole compact strip (panel), in points.
    @Published var compactPanelWidth: CGFloat = 200
    /// Width of the physical camera housing (0 on notch-less displays).
    @Published var housingWidth: CGFloat = 0
    /// Physical notch height (for DEBUG overlay — where the hardware notch ends).
    @Published var physicalNotchHeight: CGFloat = 0
    /// True while collapsed with no visible compact activity (physical-idle).
    @Published var physicalIdle: Bool = false
    /// Compact Focus timer uses content-driven asymmetric wings.
    @Published var compactFocus: Bool = false
    /// Explicit asymmetric wing widths for compact Focus and Agents.
    @Published var leftWingWidth: CGFloat = 0
    @Published var rightWingWidth: CGFloat = 0
    /// Visible surface inside the persistent transparent host. The NSPanel keeps
    /// this larger host stable while SwiftUI animates only this content.
    @Published var visibleSurfaceSize = CGSize(width: 200, height: 44)
    @Published var visibleSurfaceOffsetX: CGFloat = 0
    @Published var visibleSurfaceTopInset: CGFloat = 0

    /// Usable wing width on each side of the housing.
    var wingWidth: CGFloat {
        guard hasNotch else { return compactPanelWidth }
        return max(0, (compactPanelWidth - housingWidth) / 2)
    }
}

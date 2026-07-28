import AppKit

/// Pure inputs describing a display, decoupled from `NSScreen` so the layout
/// math can be unit-tested without real hardware.
struct DisplayMetrics: Equatable {
    /// Global frame of the screen (AppKit bottom-left origin).
    var frame: CGRect
    /// Height of the physical notch / camera housing. Zero on notch-less displays.
    var notchHeight: CGFloat
    /// Width of the physical notch. Zero on notch-less displays.
    var notchWidth: CGFloat
    var backingScaleFactor: CGFloat

    var hasNotch: Bool { notchHeight > 0 && notchWidth > 0 }
}

/// Where the panel should sit and how big it is for a given state.
struct NotchLayout: Equatable {
    /// Frame for the whole borderless panel, in global (screen) coordinates.
    var panelFrame: CGRect
    /// The compact strip rect within the panel's coordinate space (origin 0,0).
    var compactRect: CGRect
    /// The full content rect within the panel's coordinate space.
    var contentRect: CGRect
}

/// Computes notch panel geometry. Never hard-codes coordinates for a specific
/// MacBook — everything derives from the supplied `DisplayMetrics`.
enum NotchGeometryService {

    /// Effective compact width: the physical notch on notch displays, otherwise
    /// a centered pill.
    static func compactWidth(for metrics: DisplayMetrics) -> CGFloat {
        metrics.hasNotch
            ? max(metrics.notchWidth, 120)
            : DesignTokens.Metrics.pillWidth
    }

    /// Height reserved for the compact strip at the top of the EXPANDED panel.
    static func compactHeight(for metrics: DisplayMetrics) -> CGFloat {
        max(DesignTokens.Metrics.compactHeight, metrics.notchHeight)
    }

    /// Visual height of the CLOSED/compact capsule (taller than the expanded
    /// reserve so the enlarged timer + time text fit). Expanded is unaffected.
    static func compactVisualHeight(for metrics: DisplayMetrics) -> CGFloat {
        max(DesignTokens.Metrics.compactVisualHeight, metrics.notchHeight)
    }

    /// The physical-idle visible size: it must match the hardware notch exactly so
    /// a completely idle NotchDeck disappears into the notch (no capsule, no wings,
    /// no extra height). Notch-less displays fall back to a small compact strip.
    static func physicalIdleSize(for metrics: DisplayMetrics) -> CGSize {
        metrics.hasNotch
            ? CGSize(width: metrics.notchWidth, height: metrics.notchHeight)
            : CGSize(width: DesignTokens.Metrics.pillWidth, height: DesignTokens.Metrics.compactHeight)
    }

    /// Expanded content width depends on the active face.
    static func expandedWidth(for face: NotchFace) -> CGFloat {
        switch face {
        case .utilities: return DesignTokens.Metrics.expandedUtilitiesWidth
        case .agents: return DesignTokens.Metrics.expandedAgentsWidth
        }
    }

    /// Compute the panel layout for a presentation state and face.
    /// `compactExtraWidth` widens the compact/peeking strip for a live-activity
    /// (e.g. a running Pomodoro timer) while keeping it notch-like.
    /// - compactActivity: whether visible compact content exists. When false and
    ///   closed, the panel collapses to the physical-idle (notch-sized) geometry.
    /// - compactWings: content-driven asymmetric wing widths (left, right) for the
    ///   compact Focus timer. When nil, wings are the symmetric `compactExtraWidth`
    ///   split used by other activities.
    /// - compactActivityHeight: overrides the compact capsule height (Focus is
    ///   shorter). Other activities keep the default.
    static func layout(
        for metrics: DisplayMetrics,
        state: NotchPresentationState,
        face: NotchFace,
        expandedContentHeight: CGFloat,
        compactExtraWidth: CGFloat = 0,
        compactActivity: Bool = true,
        compactWings: (left: CGFloat, right: CGFloat)? = nil,
        compactActivityHeight: CGFloat? = nil
    ) -> NotchLayout {
        let cWidth = compactWidth(for: metrics) + compactExtraWidth
        let cHeight = compactHeight(for: metrics)
        let compactCapsuleHeight = compactVisualHeight(for: metrics)
        let idle = physicalIdleSize(for: metrics)

        let panelWidth: CGFloat
        let panelHeight: CGFloat
        // Strip height inside the panel: the taller capsule when closed, the
        // (unchanged) reserve when expanded.
        var stripHeight = cHeight
        // Where the physical-notch centre sits within the panel (defaults to the
        // panel centre for symmetric layouts).
        var notchCentreInPanel: CGFloat? = nil

        switch state {
        case .compact:
            if compactActivity {
                let h = compactActivityHeight ?? compactCapsuleHeight
                if let wings = compactWings, metrics.hasNotch {
                    // Content-driven asymmetric Focus capsule: left + notch + right,
                    // positioned so the notch region aligns with the hardware notch.
                    panelWidth = wings.left + metrics.notchWidth + wings.right
                    notchCentreInPanel = wings.left + metrics.notchWidth / 2
                } else {
                    panelWidth = cWidth
                }
                panelHeight = h
                stripHeight = h
            } else {
                // Physical idle: match the hardware notch exactly.
                panelWidth = idle.width
                panelHeight = idle.height
                stripHeight = idle.height
            }
        case .peeking:
            panelWidth = cWidth
            panelHeight = compactCapsuleHeight + DesignTokens.Metrics.peekExtraHeight
            stripHeight = compactCapsuleHeight
            if let wings = compactWings, metrics.hasNotch {
                notchCentreInPanel = wings.left + metrics.notchWidth / 2
            }
        case .expanded:
            panelWidth = max(cWidth, expandedWidth(for: face))
            panelHeight = min(
                max(expandedContentHeight, DesignTokens.Metrics.expandedMinHeight),
                DesignTokens.Metrics.expandedMaxHeight
            ) + cHeight
        }

        // Center on the screen so the notch region aligns with the hardware
        // notch. Symmetric layouts centre the panel; the asymmetric Focus capsule
        // pins its notch centre (not the panel centre) to the screen centre.
        let originX = metrics.frame.midX - (notchCentreInPanel ?? panelWidth / 2)
        let originY = metrics.frame.maxY - panelHeight
        let panelFrame = CGRect(x: originX.rounded(),
                                y: originY.rounded(),
                                width: panelWidth.rounded(),
                                height: panelHeight.rounded())

        // Local coordinates (panel origin at 0,0, top-left of content is high Y).
        let compactRect = CGRect(
            x: (panelWidth - cWidth) / 2,
            y: panelHeight - stripHeight,
            width: cWidth,
            height: stripHeight)

        let contentRect = CGRect(
            x: 0, y: 0,
            width: panelWidth,
            height: panelHeight)

        return NotchLayout(panelFrame: panelFrame,
                           compactRect: compactRect,
                           contentRect: contentRect)
    }

    // MARK: - NSScreen bridging

    /// Build `DisplayMetrics` from a live screen, reading the notch from the
    /// safe-area / auxiliary-area API (public since macOS 12).
    static func metrics(for screen: NSScreen) -> DisplayMetrics {
        let notchHeight = screen.safeAreaInsets.top
        var notchWidth: CGFloat = 0
        // auxiliaryTopLeftArea / Right give usable regions beside the housing.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, screen.frame.width - left.width - right.width)
        }
        return DisplayMetrics(
            frame: screen.frame,
            notchHeight: notchHeight,
            notchWidth: notchWidth,
            backingScaleFactor: screen.backingScaleFactor)
    }

    /// Pick the target screen: the one containing the mouse, or the main screen.
    static func targetScreen(preferMouse: Bool) -> NSScreen? {
        if preferMouse {
            let mouse = NSEvent.mouseLocation
            if let hit = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
                return hit
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

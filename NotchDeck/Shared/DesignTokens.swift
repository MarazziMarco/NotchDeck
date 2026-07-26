import SwiftUI

/// Central visual language for NotchDeck. Sober, dark, macOS-native.
/// No loud gradients, no gaming effects. Spring animations kept short.
enum DesignTokens {

    // MARK: Colors
    enum Palette {
        /// Near-solid black used for the compact notch so it blends with the housing.
        static let notchBlack = Color.black
        /// Deep charcoal-black surface for the expanded panel. Intentionally very
        /// dark so it reads as an extension of the physical notch, not a grey
        /// translucent window. Actual value comes from the selected
        /// `BackgroundIntensity`; this is the Deep Black default.
        static let expandedSurface = Color(white: 0.018)
        static let expandedSurfaceRaised = Color(white: 0.05)
        static let cardFill = Color.white.opacity(0.04)
        static let cardFillHover = Color.white.opacity(0.085)
        static let hairline = Color.white.opacity(0.06)
        static let separator = Color.white.opacity(0.045)
        static let primaryText = Color.white.opacity(0.96)
        static let secondaryText = Color.white.opacity(0.58)
        static let tertiaryText = Color.white.opacity(0.34)
        static let accent = Color.accentColor

        static let statusRunning = Color(red: 0.30, green: 0.72, blue: 1.0)
        static let statusAttention = Color(red: 1.0, green: 0.72, blue: 0.25)
        static let statusApproval = Color(red: 1.0, green: 0.58, blue: 0.35)
        static let statusSuccess = Color(red: 0.36, green: 0.82, blue: 0.53)
        static let statusFailure = Color(red: 1.0, green: 0.42, blue: 0.42)
        static let statusIdle = Color.white.opacity(0.35)
    }

    // MARK: Metrics
    enum Metrics {
        /// Compact capsule corner radius — visually ~half the compact visual
        /// height so the closed notch reads as a rounded capsule, not a strip.
        static let compactCornerRadius: CGFloat = 20
        static let expandedCornerRadius: CGFloat = 26
        static let contentPadding: CGFloat = 14
        static let cardCornerRadius: CGFloat = 14
        static let cardSpacing: CGFloat = 10

        /// Vertical strip reserved at the top of the EXPANDED panel (unchanged so
        /// expanded layout is untouched).
        static let compactHeight: CGFloat = 32
        /// Visual height of the CLOSED/compact capsule — a little taller than the
        /// expanded reserve so the enlarged timer + time text fit comfortably.
        static let compactVisualHeight: CGFloat = 44
        /// Minimum vertical inset inside the compact capsule.
        static let compactContentInset: CGFloat = 9
        static let peekExtraHeight: CGFloat = 14

        /// Expanded panels are wide and short — a "letterbox / capsule" feel, not
        /// a large square popover.
        static let expandedUtilitiesWidth: CGFloat = 720
        static let expandedAgentsWidth: CGFloat = 760
        static let expandedMaxHeight: CGFloat = 372   // +52: bottom breathing room
        static let expandedMinHeight: CGFloat = 274   // +44
        /// Breathing room reserved below the tallest Home module and the panel edge.
        static let bottomBreathingRoom: CGFloat = 26
        /// Home editorial edge insets.
        static let homeLeadingInset: CGFloat = 22
        static let homeTrailingInset: CGFloat = 24     // after the Mirror
        static let homeModuleGap: CGFloat = 20

        /// Extra horizontal margin so the pill on notch-less displays looks balanced.
        static let pillWidth: CGFloat = 200
    }

    // MARK: Animation
    enum Motion {
        static let expand = Animation.spring(response: 0.34, dampingFraction: 0.82)
        static let collapse = Animation.spring(response: 0.30, dampingFraction: 0.88)
        static let faceSwitch = Animation.spring(response: 0.40, dampingFraction: 0.80)
        static let subtle = Animation.easeOut(duration: 0.18)

        /// Returns `nil` when the user asked for reduced motion, so callers can
        /// apply an instant change instead of a spring.
        static func expand(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : expand }
        static func collapse(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : collapse }
        static func faceSwitch(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : faceSwitch }
    }
}

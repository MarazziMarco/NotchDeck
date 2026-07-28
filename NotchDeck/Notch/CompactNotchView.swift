import SwiftUI

/// The compact strip. Renders whatever `LiveActivityCoordinator` resolves — it
/// only shows active or attention-requiring information, never inactive module
/// icons. Content is placed in the visible wings beside the physical camera
/// housing (notched displays) or as a centred pill (notch-less). This view is
/// module-agnostic: adding a module's live activity never requires editing it.
struct CompactNotchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var live: LiveActivityCoordinator
    @EnvironmentObject private var layout: NotchLayoutInfo
    @EnvironmentObject private var diagnostics: NotchDiagnostics

    private var current: LiveActivityLayout { live.layout }

    var body: some View {
        wings(leading: leadingView, trailing: trailingView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
            .overlay { if diagnostics.enabled { compactDiagnosticOverlay } }
    }

    @ViewBuilder private var leadingView: some View {
        if let slot = current.leading {
            WingSlotView(
                slot: slot,
                reduceMotion: appState.reduceMotion,
                activateAgent: { appState.expand(face: .agents) }
            )
        }
    }
    @ViewBuilder private var trailingView: some View {
        if let slot = current.trailing {
            WingSlotView(
                slot: slot,
                reduceMotion: appState.reduceMotion,
                activateAgent: { appState.expand(face: .agents) }
            )
        }
    }

    /// Clicking a compact live activity expands the relevant face/module — but
    /// NEVER pins the panel.
    private func handleTap() {
        guard CompactNotchInteractionPolicy.containerHandlesTap(for: current) else {
            return
        }
        switch current.tapTarget {
        case .face(let face):
            appState.expand(face: face)
        case .module(let id):
            appState.expand(face: .utilities)
            appState.focusModule(id)
        case .none:
            appState.expand()
        }
    }

    // MARK: Wings

    @ViewBuilder private func wings<L: View, T: View>(leading: L, trailing: T) -> some View {
        if layout.hasNotch && current.compactAgentIndicator != nil {
            // Stable symmetric footprint with all padding *inside* each fixed wing.
            // This keeps the physical-notch exclusion centred and gives the typed
            // indicator a truthful width proposal for ViewThatFits.
            HStack(spacing: 0) {
                leading
                    .padding(.leading, CompactAgentIndicatorGeometry.outerEdgeInset)
                    .padding(.trailing, CompactAgentIndicatorGeometry.notchSafeInset)
                    .frame(width: CompactAgentIndicatorGeometry.wingWidth)
                Color.clear.frame(width: layout.housingWidth)
                trailing
                    .padding(.leading, CompactAgentIndicatorGeometry.notchSafeInset)
                    .padding(.trailing, CompactAgentIndicatorGeometry.outerEdgeInset)
                    .frame(width: CompactAgentIndicatorGeometry.wingWidth)
            }
        } else if layout.hasNotch && layout.compactFocus {
            // Dedicated compact FOCUS layout: content-driven asymmetric wings. The
            // timer icon hugs the outer-left edge (no big centred left container);
            // the time label sits just past the notch-safe inset on the right.
            HStack(spacing: 0) {
                leading
                    .frame(width: layout.leftWingWidth, alignment: .leading)
                    .padding(.leading, CompactFocusGeometry.leadingOuterPadding)
                Color.clear.frame(width: layout.housingWidth)   // physical-notch exclusion
                trailing
                    .frame(width: layout.rightWingWidth, alignment: .leading)
                    .padding(.leading, CompactFocusGeometry.notchSafeInset)
                    .padding(.trailing, CompactFocusGeometry.trailingOuterPadding)
            }
        } else if layout.hasNotch {
            // Other activities: symmetric wings; right wing clears the housing by
            // the notch-safe inset with a trailing outer pad.
            HStack(spacing: 0) {
                leading.frame(width: layout.wingWidth, alignment: .trailing).padding(.trailing, 6)
                Color.clear.frame(width: layout.housingWidth)   // exclusion zone
                trailing.frame(width: layout.wingWidth, alignment: .leading)
                    .padding(.leading, CompactWingLayout.rightWingLeadingInset(hasNotch: true))
                    .padding(.trailing, CompactWingLayout.trailingOuterPadding)
            }
        } else {
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 12)
        }
    }

    private var compactDiagnosticOverlay: some View {
        let radius = layout.compactFocus ? CompactFocusGeometry.cornerRadius
                                         : DesignTokens.Metrics.compactCornerRadius
        let leftW = layout.compactFocus ? layout.leftWingWidth : layout.wingWidth
        let rightW = layout.compactFocus ? layout.rightWingWidth : layout.wingWidth
        return ZStack(alignment: .top) {
            // Rounded clipping silhouette of the compact capsule / idle mask.
            BottomRoundedShape(radius: radius)
                .stroke(layout.physicalIdle ? .gray : .cyan, lineWidth: 1)
            // Magenta line = bottom of the physical hardware notch.
            Rectangle().fill(Color(red: 1, green: 0, blue: 1)).frame(height: 1)
                .offset(y: layout.physicalNotchHeight)
            HStack(spacing: 0) {
                if layout.hasNotch {
                    // Left wing; for Focus, the outer-leading padding band is shown.
                    ZStack(alignment: .leading) {
                        Rectangle().stroke(.green, lineWidth: 1).frame(width: leftW)
                        if layout.compactFocus {
                            Rectangle().fill(Color.yellow.opacity(0.3))
                                .frame(width: CompactFocusGeometry.leadingOuterPadding)
                        }
                    }
                    Rectangle().stroke(.red, lineWidth: 1).frame(width: layout.housingWidth)   // notch exclusion
                    // Right wing with the notch-safe inset band highlighted.
                    ZStack(alignment: .leading) {
                        Rectangle().stroke(.blue, lineWidth: 1).frame(width: rightW)
                        Rectangle().fill(Color.orange.opacity(0.3))
                            .frame(width: layout.compactFocus ? CompactFocusGeometry.notchSafeInset
                                                              : CompactWingLayout.notchSafeInset)
                    }
                } else {
                    Rectangle().stroke(.yellow, lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Pure compact-wing geometry. Only notched displays get the extra safe inset;
/// rectangular / external screens keep the normal tight spacing.
enum CompactWingLayout {
    /// Clearance between the physical-notch exclusion zone and the first icon of
    /// the right wing (≈22pt on notched displays).
    static let notchSafeInset: CGFloat = 22
    static let normalInset: CGFloat = 6
    static let trailingOuterPadding: CGFloat = 16

    static func rightWingLeadingInset(hasNotch: Bool) -> CGFloat {
        hasNotch ? notchSafeInset : normalInset
    }
    /// X where the right wing content starts, given the housing's right edge.
    static func rightWingStartX(housingMaxX: CGFloat, hasNotch: Bool) -> CGFloat {
        housingMaxX + rightWingLeadingInset(hasNotch: hasNotch)
    }
}

/// One authoritative geometry model for the CLOSED compact Focus timer. All
/// visible-frame, clipping, wing-width and hit-test math for compact Focus
/// derives from here — no independent constants scattered across views.
enum CompactFocusGeometry {
    static let visualHeight: CGFloat = 39         // shorter capsule (was 44)
    static let cornerRadius: CGFloat = 17         // ≈ half of 39 → clearly rounded
    static let leadingOuterPadding: CGFloat = 9   // icon sits near the outer left edge
    static let trailingOuterPadding: CGFloat = 12
    static let notchSafeInset: CGFloat = 22       // clearance from the physical notch
    static let timerDiameter: CGFloat = 22
    static let timerStroke: CGFloat = 2.5
    static let timerGlyphSize: CGFloat = 11.5
    static let timeFontSize: CGFloat = 20
    /// Measured width for "00:00" at 20pt monospaced semibold, plus a small margin.
    static let timeTextWidth: CGFloat = 60

    /// Content-driven wings — NOT equal. Left hugs the icon; right fits the text.
    static var leftWingWidth: CGFloat { leadingOuterPadding + timerDiameter + notchSafeInset }
    static var rightWingWidth: CGFloat { notchSafeInset + timeTextWidth + trailingOuterPadding }
    /// Total width added beyond the physical notch.
    static var totalExtraWidth: CGFloat { leftWingWidth + rightWingWidth }
}

/// Sizing for the compact Focus timer content — a genuine ring + MM:SS, not a
/// tiny status dot. Values mirror `CompactFocusGeometry` (the ring and the
/// emphasized MM:SS are Focus-specific in practice).
enum CompactTimerLayout {
    static let ringDiameter: CGFloat = CompactFocusGeometry.timerDiameter   // 22
    static let ringStroke: CGFloat = CompactFocusGeometry.timerStroke       // 2.5
    static let glyphSize: CGFloat = CompactFocusGeometry.timerGlyphSize     // 11.5
    static let symbolSize: CGFloat = 13       // non-progress compact symbol
    static let timeTextSize: CGFloat = CompactFocusGeometry.timeFontSize    // 20
    static let timeTextMinSize: CGFloat = 18  // readable floor (never below this)
    static let timeTextMinWidth: CGFloat = 56 // room for "00:00" at 20pt mono
    static let labelTextSize: CGFloat = 13    // status labels (e.g. "2 agents active")
    static let providerLogoSize: CGFloat = 18

    enum Variant: Equatable { case wide, medium, narrow }
    static func variant(wingWidth: CGFloat) -> Variant {
        if wingWidth >= 96 { return .wide }
        if wingWidth >= 66 { return .medium }
        return .narrow
    }
    /// Time text size for a variant — never below the readable floor.
    static func timeTextSize(for variant: Variant) -> CGFloat {
        variant == .narrow ? timeTextMinSize : timeTextSize
    }
    /// Whether a secondary control (overflow / phase indicator) has room; it is
    /// dropped before the primary time text is shrunk.
    static func showsSecondary(_ variant: Variant) -> Bool { variant == .wide }
}

/// Renders one `WingSlot`: optional progress ring around a symbol, optional
/// text, optional numeric badge, optional pulse.
struct WingSlotView: View {
    let slot: WingSlot
    var reduceMotion: Bool = false
    var activateAgent: () -> Void = {}
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            if let model = slot.compactAgentIndicator {
                CompactAgentIndicatorView(
                    model: model,
                    accent: slot.compactAgentAccent ?? .orange,
                    activate: activateAgent
                )
            } else if let vendor = slot.providerVendor {
                AgentProviderLogo(appearance: AgentProviderAppearanceRegistry.appearance(vendor),
                                  size: CompactTimerLayout.providerLogoSize)
                    .overlay(alignment: .topTrailing) {
                        if slot.pulse && slot.tint == .approval {
                            Circle().fill(slot.tint.color).frame(width: 6, height: 6).offset(x: 3, y: -3)
                        }
                    }
            } else if let symbol = slot.symbol {
                ZStack {
                    if let progress = slot.progress {
                        // A real progress ring, not a tiny status dot.
                        ProgressRing(progress: progress, lineWidth: CompactTimerLayout.ringStroke, tint: slot.tint.color)
                            .frame(width: CompactTimerLayout.ringDiameter, height: CompactTimerLayout.ringDiameter)
                    }
                    Image(systemName: symbol)
                        .font(.system(size: slot.progress == nil ? CompactTimerLayout.symbolSize
                                            : CompactTimerLayout.glyphSize, weight: .medium))
                        .foregroundStyle(slot.tint.color)
                        .opacity(slot.pulse && pulsing ? 0.45 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if let badge = slot.badge {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(2)
                            .background(slot.tint.color, in: Circle())
                            .foregroundStyle(.black)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            if let text = slot.text {
                Text(text)
                    .font(.system(size: slot.emphasize ? CompactTimerLayout.timeTextSize
                                        : CompactTimerLayout.labelTextSize, weight: .semibold))
                    .modifier(MonoDigits(on: slot.monospacedDigits))
                    // The MM:SS is a PRIMARY element: large, high-contrast, mono
                    // digits (stable width), never shrunk or truncated.
                    .foregroundStyle(slot.emphasize ? DesignTokens.Palette.primaryText
                                     : (slot.symbol == nil ? slot.tint.color : DesignTokens.Palette.primaryText))
                    .lineLimit(1)
                    .fixedSize(horizontal: slot.emphasize, vertical: false)
                    .frame(minWidth: slot.emphasize ? CompactTimerLayout.timeTextMinWidth : nil,
                           alignment: slot.symbol == nil ? .leading : .center)
            }
        }
        .onAppear {
            if slot.pulse && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { pulsing = false }
        }
    }
}

private struct MonoDigits: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { on ? AnyView(content.monospacedDigit()) : AnyView(content) }
}

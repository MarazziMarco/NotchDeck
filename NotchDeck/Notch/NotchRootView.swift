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
            visibleSurface
                .frame(
                    width: notchLayout.visibleSurfaceSize.width,
                    height: notchLayout.visibleSurfaceSize.height
                )
                .offset(
                    x: notchLayout.visibleSurfaceOffsetX,
                    y: notchLayout.visibleSurfaceTopInset
                )
                .clipShape(BottomRoundedShape(radius: surface.cornerRadius))
                .animation(
                    DesignTokens.Motion.expand(reduceMotion: appState.reduceMotion),
                    value: notchLayout.visibleSurfaceSize
                )
                .animation(
                    DesignTokens.Motion.expand(reduceMotion: appState.reduceMotion),
                    value: notchLayout.visibleSurfaceOffsetX
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var visibleSurface: some View {
        ZStack(alignment: .top) {
            // The host stays transparent. This is the sole opaque surface.
            NotchSurface(descriptor: surface)

            ZStack(alignment: .top) {
                switch appState.presentation {
                case .compact:
                    CompactNotchView().transition(.identity)
                case .peeking:
                    ApprovalPeekView().transition(.identity)
                case .expanded:
                    ExpandedNotchView().transition(.identity)
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
        .animation(DesignTokens.Motion.expand(reduceMotion: appState.reduceMotion),
                   value: appState.presentation)
    }
}

/// Event-driven approval strip. Every action resolves the projected transaction
/// back through the existing store/coordinator by `session UUID + transactionID`.
struct ApprovalPeekView: View {
    @EnvironmentObject private var peek: ApprovalPeekCoordinator
    @EnvironmentObject private var store: AgentSessionStore
    @EnvironmentObject private var agents: AgentCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notchLayout: NotchLayoutInfo

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: appState.reduceMotion ? 1 : 0.25
        )) { context in
            if let item = peek.snapshot.visible {
                content(
                    item: item,
                    presentation: ApprovalPeekPresentation(
                        item: item,
                        totalCount: peek.snapshot.totalCount
                    ),
                    now: context.date
                )
            }
        }
        .onHover { hovering in
            peek.setHovering(hovering)
        }
        .onDisappear {
            peek.setHovering(false)
        }
    }

    private func content(
        item: ApprovalPeekItem,
        presentation: ApprovalPeekPresentation,
        now: Date
    ) -> some View {
        let actionable = item.isLocallyActionable(at: now)
        let motion = ApprovalPeekMotionPolicy(reduceMotion: appState.reduceMotion)
        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                AgentProviderLogo(
                    appearance: AgentProviderAppearanceRegistry.appearance(
                        kind: item.approval.provider,
                        hint: nil
                    ),
                    size: 26,
                    darkBackground: true
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(presentation.providerName)
                            .font(.system(size: 11, weight: .bold))
                        Text(presentation.projectName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.Palette.secondaryText)
                            .lineLimit(1)
                        if let queue = presentation.queueText {
                            Text(queue)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(presentation.toolName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.tertiaryText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.actionSummary)
                        .font(.system(
                            size: 11,
                            weight: .medium,
                            design: presentation.isCommand ? .monospaced : .default
                        ))
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                        .lineLimit(peek.isHovering ? 3 : 1)
                        .truncationMode(.middle)
                    if peek.isHovering {
                        Text(item.projectPath.isEmpty ? "Working directory unavailable" : item.projectPath)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(DesignTokens.Palette.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(presentation.providerName) session · \(item.approval.sessionID)")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignTokens.Palette.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.expand(face: .agents)
                }

                actionControls(
                    item: item,
                    presentation: presentation,
                    actionable: actionable
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, notchLayout.hasNotch ? max(7, notchLayout.physicalNotchHeight) : 9)
            .padding(.bottom, 7)

            progressBar(item: item, now: now, animates: motion.animatesProgress)
        }
        .foregroundStyle(DesignTokens.Palette.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.groupAccessibilityLabel)
        .animation(
            motion.animatesHoverGrowth ? .easeOut(duration: 0.18) : nil,
            value: peek.isHovering
        )
    }

    @ViewBuilder
    private func actionControls(
        item: ApprovalPeekItem,
        presentation: ApprovalPeekPresentation,
        actionable: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                focusTerminal(sessionID: item.sessionID)
            } label: {
                Label("Terminal", systemImage: "macwindow.on.rectangle")
            }
            .accessibilityLabel(presentation.focusAccessibilityLabel)
            .help("Focus the existing terminal session")

            if actionable {
                // Allow is deliberately internal; Deny occupies the trailing
                // cursor-entry edge and the two decisions have clear separation.
                decisionButton(
                    "Allow",
                    symbol: "checkmark",
                    tint: DesignTokens.Palette.statusSuccess,
                    accessibilityLabel: presentation.allowAccessibilityLabel
                ) {
                    decide(item: item, allow: true)
                }
                decisionButton(
                    "Deny",
                    symbol: "xmark",
                    tint: DesignTokens.Palette.statusFailure,
                    accessibilityLabel: presentation.denyAccessibilityLabel
                ) {
                    decide(item: item, allow: false)
                }
            } else {
                Text(presentation.expiredStatus)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.statusAttention)
                    .accessibilityLabel(
                        "\(presentation.expiredStatus); approval is no longer actionable in NotchDeck"
                    )
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func decisionButton(
        _ title: String,
        symbol: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(0.16), in: Capsule())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func progressBar(
        item: ApprovalPeekItem,
        now: Date,
        animates: Bool
    ) -> some View {
        GeometryReader { proxy in
            let fraction = ApprovalPeekProgress.fraction(
                receivedAt: item.approval.receivedAt,
                deadline: item.approval.actionDeadline,
                now: now
            )
            ZStack(alignment: .leading) {
                Color.white.opacity(0.08)
                Color.accentColor
                    .frame(width: proxy.size.width * fraction)
            }
            .animation(animates ? .linear(duration: 0.25) : nil, value: fraction)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private func decide(item: ApprovalPeekItem, allow: Bool) {
        Task {
            _ = await agents.decide(
                sessionID: item.sessionID,
                transactionID: item.transactionID,
                allow: allow
            )
        }
    }

    private func focusTerminal(sessionID: UUID) {
        guard let item = peek.snapshot.visible,
              item.sessionID == sessionID,
              let session = ApprovalPeekFocus.target(
                for: item,
                sessions: store.sessions
              ) else { return }
        agents.focusTerminal(session)
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

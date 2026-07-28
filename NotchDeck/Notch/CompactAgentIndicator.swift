import SwiftUI

/// Plain, count-only inputs for the compact Agents surface. Provider, project,
/// session and tool names never cross this presentation boundary.
struct CompactAgentIndicatorInputs: Equatable {
    var activeSessionCount: Int = 0
    var pendingApprovalCount: Int = 0
    var inputRequiredCount: Int = 0
    var transactionStates: [PendingApproval.ResponseState] = []
    var displayPreference: CompactAgentsDisplay = .activeCount

    static func resolve(
        activeSessions: [AgentSession],
        displayPreference: CompactAgentsDisplay
    ) -> Self {
        let approvals = activeSessions.flatMap { session -> [PendingApproval] in
            [session.approval].compactMap { $0 } + (session.queuedApprovals ?? [])
        }
        return Self(
            activeSessionCount: activeSessions.count,
            pendingApprovalCount: approvals.filter { $0.state == .pending }.count,
            inputRequiredCount: activeSessions.filter { $0.status == .waitingForInput }.count,
            transactionStates: approvals.map(\.state),
            displayPreference: displayPreference
        )
    }
}

/// The one normalized Agents state that may appear beside the physical notch.
/// Higher-priority cases replace lower-priority information instead of combining
/// unrelated labels, badges and counters in the same constrained wing.
enum CompactAgentIndicatorModel: Equatable {
    case hidden
    case activeSessions(count: Int)
    case approvalRequired(count: Int)
    case inputRequired(count: Int)
    case deliveryInProgress
    case deliveryFailed
    case terminalFallback

    static func resolve(_ input: CompactAgentIndicatorInputs) -> Self {
        let states = input.transactionStates
        if states.contains(.deliveryFailed) {
            return .deliveryFailed
        }
        if states.contains(.fellBack) {
            return .terminalFallback
        }

        let approvals = max(0, input.pendingApprovalCount)
        if approvals > 0 {
            return .approvalRequired(count: approvals)
        }

        let inputs = max(0, input.inputRequiredCount)
        if inputs > 0 {
            return .inputRequired(count: inputs)
        }

        if states.contains(where: { [.sending, .sent, .helperExited].contains($0) }) {
            return .deliveryInProgress
        }

        let active = max(0, input.activeSessionCount)
        guard input.displayPreference != .hidden, active > 0 else {
            return .hidden
        }
        return .activeSessions(count: active)
    }

    var isVisible: Bool { self != .hidden }

    /// Ordinary session presence yields to the protected Focus timer. Every other
    /// visible state is actionable/progress information and remains visible.
    var overridesFocus: Bool {
        switch self {
        case .hidden, .activeSessions: return false
        default: return true
        }
    }

    var compactCountText: String? {
        let count: Int
        switch self {
        case .activeSessions(let value),
             .approvalRequired(let value),
             .inputRequired(let value):
            count = max(0, value)
        default:
            return nil
        }
        return count > 9 ? "9+" : "\(count)"
    }

    var conciseLabel: String? {
        switch self {
        case .hidden, .activeSessions: return nil
        case .approvalRequired: return "Approval"
        case .inputRequired: return "Input"
        case .deliveryInProgress: return "Sent"
        case .deliveryFailed: return "Failed"
        case .terminalFallback: return "Terminal"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .hidden:
            return ""
        case .activeSessions(let count):
            return count == 1 ? "1 active agent session" : "\(count) active agent sessions"
        case .approvalRequired(let count):
            return count == 1 ? "1 agent approval required" : "\(count) agent approvals required"
        case .inputRequired(let count):
            return count == 1 ? "1 agent input required" : "\(count) agent inputs required"
        case .deliveryInProgress:
            return "Agent response delivery in progress"
        case .deliveryFailed:
            return "Agent approval delivery failed"
        case .terminalFallback:
            return "Respond to agent in Terminal"
        }
    }

    var symbolName: String {
        switch self {
        case .hidden, .activeSessions:
            return "chevron.left.forwardslash.chevron.right"
        case .approvalRequired:
            return "checkmark.shield"
        case .inputRequired:
            return "text.cursor"
        case .deliveryInProgress:
            return "paperplane.fill"
        case .deliveryFailed:
            return "exclamationmark.triangle.fill"
        case .terminalFallback:
            return "terminal.fill"
        }
    }

    func tint(activeAccent: AgentCompactAccent) -> StatusTint {
        switch self {
        case .hidden: return .neutral
        case .activeSessions: return activeAccent == .orange ? .agentActive : .neutral
        case .approvalRequired: return .approval
        case .inputRequired: return .attention
        case .deliveryInProgress: return .neutral
        case .deliveryFailed: return .failure
        case .terminalFallback: return .attention
        }
    }
}

/// Stable, notch-safe footprint for every visible compact Agents state. Counts
/// change content, never panel width. Insets live *inside* the fixed right wing.
enum CompactAgentIndicatorGeometry {
    static let visualHeight: CGFloat = DesignTokens.Metrics.compactVisualHeight
    static let wingWidth: CGFloat = 84
    static let totalExtraWidth: CGFloat = wingWidth * 2
    static let notchSafeInset: CGFloat = 20
    static let outerEdgeInset: CGFloat = 14
    static let iconSize: CGFloat = 17
    static let indicatorHeight: CGFloat = 26
    static let standardSpacing: CGFloat = 5
    static let badgeHeight: CGFloat = 14
    static let badgeMinimumWidth: CGFloat = 14

    static let rightWingRect = CGRect(x: 0, y: 0, width: wingWidth, height: visualHeight)
    static let rightWingContentRect = CGRect(
        x: notchSafeInset,
        y: 0,
        width: wingWidth - notchSafeInset - outerEdgeInset,
        height: visualHeight
    )

    static func extraWidth(for model: CompactAgentIndicatorModel) -> CGFloat {
        model.isVisible ? totalExtraWidth : 0
    }
}

/// Converts the normalized presentation model into one typed live-activity slot.
/// No second textual/badge model is created here.
enum CompactAgentActivityFactory {
    static func make(
        for model: CompactAgentIndicatorModel,
        accent: AgentCompactAccent = .orange
    ) -> ResolvedActivity? {
        guard model.isVisible else { return nil }

        let priority: LiveActivityPriority
        switch model {
        case .deliveryFailed, .terminalFallback, .approvalRequired:
            priority = .approval
        case .inputRequired:
            priority = .input
        case .deliveryInProgress:
            priority = .agentDelivery
        case .activeSessions:
            priority = .agentsRunning
        case .hidden:
            return nil
        }

        return ResolvedActivity(
            id: "agents",
            priority: priority,
            slot: WingSlot(
                compactAgentIndicator: model,
                compactAgentAccent: accent
            ),
            preferredWing: .trailing,
            attention: model.overridesFocus,
            tapTarget: .face(.agents),
            exclusive: model.overridesFocus
        )
    }
}

/// Geometry changes are observed by semantic footprint, not by mutable text or
/// by slot count alone. This catches Focus ↔ urgent Agents transitions even when
/// both layouts happen to occupy two slots.
enum CompactGeometrySignature: Equatable {
    case idle
    case focus
    case agent
    case standard(slotCount: Int)

    static func resolve(_ layout: LiveActivityLayout) -> Self {
        if layout.isEmpty { return .idle }
        if layout.isFocusTimer { return .focus }
        if layout.compactAgentIndicator != nil { return .agent }
        let count = (layout.leading == nil ? 0 : 1) + (layout.trailing == nil ? 0 : 1)
        return .standard(slotCount: count)
    }
}

/// Exactly one content subtree owns a presentation state. Peeking intentionally
/// keeps compact content; expanded never retains a compact indicator.
enum CompactNotchPresentationPolicy {
    static func showsCompact(in state: NotchPresentationState) -> Bool {
        state != .expanded
    }

    static func showsExpanded(in state: NotchPresentationState) -> Bool {
        state == .expanded
    }
}

/// The generic compact surface keeps its established whole-strip interaction,
/// while a typed Agents indicator owns a deliberately small explicit button.
/// This prevents empty wings and the physical-notch exclusion from becoming an
/// invisible shortcut to the Agents workspace.
enum CompactNotchInteractionPolicy {
    static func containerHandlesTap(for layout: LiveActivityLayout) -> Bool {
        layout.compactAgentIndicator == nil
    }
}

/// Icon-led adaptive indicator. Each candidate is intrinsically sized, so
/// `ViewThatFits` selects a complete variant rather than truncating a larger one.
struct CompactAgentIndicatorView: View {
    let model: CompactAgentIndicatorModel
    var accent: AgentCompactAccent = .orange
    let activate: () -> Void

    var body: some View {
        Button(action: activate) {
            ViewThatFits(in: .horizontal) {
                labelledVariant
                countedVariant
                badgeVariant
            }
            .frame(height: CompactAgentIndicatorGeometry.indicatorHeight)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.accessibilityLabel))
    }

    private var statusIcon: some View {
        Image(systemName: model.symbolName)
            .font(.system(
                size: CompactAgentIndicatorGeometry.iconSize,
                weight: .semibold
            ))
            .foregroundStyle(model.tint(activeAccent: accent).color)
            .accessibilityHidden(true)
    }

    private var labelledVariant: some View {
        HStack(spacing: CompactAgentIndicatorGeometry.standardSpacing) {
            statusIcon
            if let label = model.conciseLabel {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                    .fixedSize()
            }
            countText
        }
        .fixedSize()
    }

    private var countedVariant: some View {
        HStack(spacing: CompactAgentIndicatorGeometry.standardSpacing) {
            statusIcon
            countText
        }
        .fixedSize()
    }

    private var badgeVariant: some View {
        statusIcon
            .frame(
                width: CompactAgentIndicatorGeometry.indicatorHeight,
                height: CompactAgentIndicatorGeometry.indicatorHeight
            )
            .overlay(alignment: .topTrailing) {
                if let count = model.compactCountText {
                    Text(count)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .frame(
                            minWidth: CompactAgentIndicatorGeometry.badgeMinimumWidth,
                            minHeight: CompactAgentIndicatorGeometry.badgeHeight
                        )
                        .padding(.horizontal, count == "9+" ? 2 : 0)
                        .background(model.tint(activeAccent: accent).color, in: Capsule())
                        .offset(x: 7, y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, model.compactCountText == nil ? 0 : 7)
    }

    @ViewBuilder private var countText: some View {
        if let count = model.compactCountText {
            Text(count)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.primaryText)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

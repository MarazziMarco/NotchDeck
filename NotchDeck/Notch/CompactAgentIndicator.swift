import SwiftUI

/// Normalized inputs for the compact Agents surface. Provider presence crosses
/// this boundary; project, session and tool names never do.
struct CompactAgentIndicatorInputs: Equatable {
    var activeSessionCount: Int = 0
    var pendingApprovalCount: Int = 0
    var inputRequiredCount: Int = 0
    var transactionStates: [PendingApproval.ResponseState] = []
    var displayPreference: CompactAgentsDisplay = .activeCount
    var providers: CompactAgentProviderPresence = .init()

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
            displayPreference: displayPreference,
            providers: CompactAgentProviderPresence(activeSessions: activeSessions)
        )
    }
}

/// The compact notch intentionally exposes provider presence, never session
/// counts or private session metadata. Claude owns the left wing and Codex the
/// right wing, so changes in session count cannot move either mark.
struct CompactAgentProviderPresence: Equatable {
    var showsClaude = false
    var showsCodex = false

    init(showsClaude: Bool = false, showsCodex: Bool = false) {
        self.showsClaude = showsClaude
        self.showsCodex = showsCodex
    }

    init(activeSessions: [AgentSession]) {
        showsClaude = activeSessions.contains { $0.provider == .claudeCode }
        showsCodex = activeSessions.contains { $0.provider == .codex }
    }

    var leadingVendor: AgentVendor? { showsClaude ? .claudeCode : nil }
    var trailingVendor: AgentVendor? { showsCodex ? .codex : nil }
    var isEmpty: Bool { !showsClaude && !showsCodex }
}

struct CompactAgentPresentation: Equatable {
    var state: CompactAgentIndicatorModel
    var providers: CompactAgentProviderPresence

    var isVisible: Bool { state.isVisible && !providers.isEmpty }
    var accessibilityLabel: String {
        let names = [
            providers.showsClaude ? "Claude Code" : nil,
            providers.showsCodex ? "Codex" : nil
        ].compactMap { $0 }
        let providerText = names.joined(separator: " and ")
        switch state {
        case .approvalRequired:
            return "\(providerText) approval required"
        case .inputRequired:
            return "\(providerText) input required"
        case .deliveryInProgress:
            return "\(providerText) response delivery in progress"
        case .deliveryFailed:
            return "\(providerText) approval delivery failed"
        case .terminalFallback:
            return "Respond to \(providerText) in Terminal"
        case .activeSessions:
            return "\(providerText) active"
        case .hidden:
            return ""
        }
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

        if states.contains(where: {
            [.sending, .sent, .providerOutputClosed, .helperTerminated, .helperExited].contains($0)
        }) {
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

/// Stable, notch-safe provider wings. Session count never changes their size.
enum CompactAgentIndicatorGeometry {
    static let wingWidth: CGFloat = 30
    static let totalExtraWidth: CGFloat = wingWidth * 2
    static let notchSafeInset: CGFloat = 5
    static let outerEdgeInset: CGFloat = 5
    static let iconSize: CGFloat = 20

    static let rightWingRect = CGRect(x: 0, y: 0, width: wingWidth, height: 32)
    static let rightWingContentRect = CGRect(
        x: notchSafeInset,
        y: 0,
        width: wingWidth - notchSafeInset - outerEdgeInset,
        height: 32
    )

    static func visualHeight(for metrics: DisplayMetrics) -> CGFloat {
        metrics.hasNotch ? metrics.notchHeight : DesignTokens.Metrics.compactHeight
    }

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

    static func make(
        for presentation: CompactAgentPresentation,
        accent: AgentCompactAccent = .orange
    ) -> ResolvedActivity? {
        guard presentation.isVisible else { return nil }

        let priority: LiveActivityPriority
        switch presentation.state {
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

        let urgent = presentation.state.overridesFocus
        func slot(_ vendor: AgentVendor) -> WingSlot {
            WingSlot(
                pulse: urgent,
                providerVendor: vendor,
                compactAgentIndicator: presentation.state,
                compactAgentAccent: accent
            )
        }
        let leading = presentation.providers.leadingVendor.map(slot)
        let trailing = presentation.providers.trailingVendor.map(slot)
        let primary = trailing ?? leading!
        return ResolvedActivity(
            id: "agents",
            priority: priority,
            slot: primary,
            preferredWing: trailing != nil ? .trailing : .leading,
            attention: urgent,
            tapTarget: .face(.agents),
            exclusive: urgent,
            splitLeading: leading,
            splitTrailing: trailing
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

/// Provider-only compact mark. Urgent states use the same stable footprint and a
/// restrained breath; no count, text or badge is ever mounted.
struct CompactAgentIndicatorView: View {
    let vendor: AgentVendor
    let model: CompactAgentIndicatorModel
    var reduceMotion = false
    let activate: () -> Void
    @State private var breathing = false

    var body: some View {
        Button(action: activate) {
            AgentProviderLogo(
                appearance: AgentProviderAppearanceRegistry.appearance(vendor),
                size: CompactAgentIndicatorGeometry.iconSize,
                darkBackground: true
            )
            .scaleEffect(breathing ? 1.035 : 1)
            .opacity(breathing ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
        .onChange(of: model) { _, _ in updateAnimation() }
    }

    private var accessibilityLabel: String {
        let provider = AgentProviderAppearanceRegistry.appearance(vendor).displayName
        switch model {
        case .approvalRequired: return "\(provider) approval required"
        case .inputRequired: return "\(provider) input required"
        case .deliveryInProgress: return "\(provider) response delivery in progress"
        case .deliveryFailed: return "\(provider) approval delivery failed"
        case .terminalFallback: return "Respond to \(provider) in Terminal"
        case .activeSessions: return "\(provider) active"
        case .hidden: return ""
        }
    }

    private func updateAnimation() {
        breathing = false
        guard model != .hidden, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

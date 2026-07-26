import SwiftUI

/// Actions a card can trigger. Presence of a closure decides whether a control
/// is shown, so managed / connected / external sessions render appropriately.
struct AgentCardActions {
    var focusTerminal: () -> Void        // ALWAYS visible primary
    var openProject: () -> Void
    var approve: (() -> Void)?
    var deny: (() -> Void)?
    var resume: (() -> Void)?
    var interrupt: (() -> Void)?
    var followUp: (() -> Void)?
}

/// One agent session as a dense horizontal card. A genuine pending approval
/// (only from a PermissionRequest) expands with Allow/Deny; ordinary running
/// cards never show decision buttons. Focus Terminal is always visible and is
/// never buried in the overflow menu.
struct AgentSessionCard: View {
    let session: AgentSession
    var maxPreviewLines: Int = 2
    var showPreview: Bool = true
    var approvalSending: Bool = false
    let actions: AgentCardActions
    @State private var hovering = false

    private var genuineApproval: Bool {
        session.hasLiveApproval && session.approval?.state == .pending
            && actions.approve != nil && actions.deny != nil
    }
    private var fellBack: Bool { session.approval?.state == .fellBack }
    private var deliveryState: PendingApproval.ResponseState? { session.approval?.state }

    private func statusRow(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(tint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            headerRow
            if genuineApproval { approvalRow }
            else if deliveryState == .sending { statusRow("Sending approval…", "arrow.up.circle", DesignTokens.Palette.secondaryText) }
            else if deliveryState == .delivered { statusRow("Approved", "checkmark.circle.fill", DesignTokens.Palette.statusSuccess) }
            else if deliveryState == .deliveryFailed { statusRow("Approval could not be delivered — answer in Terminal", "exclamationmark.triangle.fill", DesignTokens.Palette.statusFailure) }
            else if deliveryState == .expired { statusRow("Request expired", "clock.badge.xmark", DesignTokens.Palette.tertiaryText) }
            else if fellBack { waitingInTerminalRow }
        }
        .padding(11)
        .background(hovering ? DesignTokens.Palette.cardFillHover : DesignTokens.Palette.cardFill,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: genuineApproval ? 1.4 : 0.6))
        .onHover { hovering = $0 }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentProviderLogo(session: session, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName.isEmpty ? session.title : session.projectName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.primaryText).lineLimit(1)
                    StatusBadge(status: displayStatus)
                }
                Text("\(session.status.label) · \(session.appearance.displayName)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText).lineLimit(1)
                if showPreview, let summary = session.latestSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(maxPreviewLines)
                        .truncationMode(.middle)
                }
                if genuineApproval { debugApprovalLabel }
                debugPresenceLabel
            }
            Spacer(minLength: 6)
            trailing
        }
    }

    /// Status shown in the badge (reflects the terminal-fallback hand-off).
    private var displayStatus: AgentSessionStatus {
        fellBack ? .waitingForInput : session.status
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            focusTerminalButton
            overflow
        }
    }

    private var focusTerminalButton: some View {
        Button(action: actions.focusTerminal) {
            Label("Focus Terminal", systemImage: "macwindow.on.rectangle")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(DesignTokens.Palette.cardFillHover, in: Capsule())
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .buttonStyle(.plain)
        .help(session.terminalTTY != nil
              ? "Bring the exact terminal tab (\(session.terminalTTY!)) to the front"
              : "Exact terminal association unavailable")
    }

    @ViewBuilder private var overflow: some View {
        if actions.resume != nil || actions.interrupt != nil || actions.followUp != nil || !session.projectPath.isEmpty {
            Menu {
                Button("Open project", action: actions.openProject)
                if let resume = actions.resume { Button("Resume", action: resume) }
                if let interrupt = actions.interrupt { Button("Stop", action: interrupt) }
                if let followUp = actions.followUp { Divider(); Button("Send follow-up…", action: followUp) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).frame(width: 20).fixedSize()
        }
    }

    // MARK: Approval

    private var approvalRow: some View {
        // DEBUG safety: an approval card must originate from a PermissionRequest.
        assert(session.approval?.rawEventName == "PermissionRequest",
               "Approval card without a PermissionRequest-backed PendingApproval")
        return VStack(alignment: .leading, spacing: 6) {
            if let summary = session.approval?.summary, !summary.isEmpty {
                Text(summary).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.primaryText).lineLimit(3)
            }
            HStack(spacing: 8) {
                if let deadline = session.approval?.fallbackDeadline {
                    Label("Terminal prompt in \(secondsRemaining(deadline))s", systemImage: "timer")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.Palette.statusAttention)
                }
                Spacer(minLength: 0)
                if approvalSending {
                    Label("Sending…", systemImage: "arrow.up.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                } else {
                    decisionButton("Deny", "xmark", DesignTokens.Palette.statusFailure, actions.deny)
                    decisionButton("Allow", "checkmark", DesignTokens.Palette.statusSuccess, actions.approve)
                }
            }
        }
    }

    private var waitingInTerminalRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.forward")
            Text("Waiting in Terminal — answer the native prompt")
        }
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Palette.statusAttention)
    }

    private var debugApprovalLabel: some View {
        #if DEBUG
        return Text("PermissionRequest · request \(String((session.approval?.requestID ?? "").prefix(6)))")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(DesignTokens.Palette.tertiaryText)
        #else
        return EmptyView()
        #endif
    }

    /// DEBUG-only presence/debounce readout (miss counter toward Recent).
    private var debugPresenceLabel: some View {
        #if DEBUG
        return Text("presence \(session.terminalPresence.rawValue) · miss \(session.terminalMissCount)/\(TerminalPresenceDebounce.missThreshold)")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(DesignTokens.Palette.tertiaryText)
        #else
        return EmptyView()
        #endif
    }

    private func decisionButton(_ title: String, _ icon: String, _ tint: Color,
                                _ action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(tint.opacity(0.22), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(action == nil || approvalSending)
    }

    private func secondsRemaining(_ deadline: Date) -> Int {
        max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    private var borderColor: Color {
        if genuineApproval { return DesignTokens.Palette.statusApproval }
        return DesignTokens.Palette.hairline
    }
}

/// Colored status chip.
struct StatusBadge: View {
    let status: AgentSessionStatus
    var body: some View {
        Text(status.label)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(status.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

extension AgentSessionStatus {
    var tint: Color {
        switch self {
        case .waitingForApproval: return DesignTokens.Palette.statusApproval
        case .waitingForInput: return DesignTokens.Palette.statusAttention
        case .running, .starting: return DesignTokens.Palette.statusRunning
        case .completed: return DesignTokens.Palette.statusSuccess
        case .failed: return DesignTokens.Palette.statusFailure
        case .interrupted, .idle, .unavailable: return DesignTokens.Palette.statusIdle
        }
    }
}

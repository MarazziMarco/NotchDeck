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

/// Pure, testable semantic presentation used by both visual labels and
/// accessibility. It prevents status duplication and provider-name mixups.
struct AgentCardPresentation: Equatable {
    let lifecycleLabel: String
    let statusLine: String
    let preview: String?
    let deliveryLabel: String?
    let terminalNotice: String?
    let focusAccessibilityLabel: String

    init(session: AgentSession, bucket: AgentBucket) {
        lifecycleLabel = bucket == .recent ? "Recent" : "Active"
        let provider = session.appearance.displayName
        let state: String
        switch session.approval?.state {
        case .pending: state = "Permission requested"
        case .sending: state = "Sending decision"
        case .sent, .providerOutputClosed, .helperTerminated, .helperExited: state = "Decision sent"
        case .delivered: state = "Continued"
        case .deliveryFailed: state = "Delivery failed"
        case .fellBack: state = "Respond in Terminal"
        case .expired: state = "Respond in Terminal"
        case .cancelled: state = "Cancelled"
        case .answered: state = "Answered"
        case .none: state = session.status.label
        }
        statusLine = "\(provider) · \(state)"

        if session.approval != nil {
            preview = nil
        } else {
            let summary = session.latestSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
            preview = (summary?.isEmpty == false && summary != state) ? summary : nil
        }

        switch session.approval?.state {
        case .sending: deliveryLabel = "Sending to \(provider)…"
        case .sent, .providerOutputClosed, .helperTerminated, .helperExited: deliveryLabel = "Sent to \(provider)"
        case .delivered: deliveryLabel = "\(provider) continued"
        case .deliveryFailed: deliveryLabel = "Delivery failed — answer in Terminal"
        case .expired: deliveryLabel = "No longer actionable in NotchDeck"
        default: deliveryLabel = nil
        }
        terminalNotice = session.terminalTTY == nil ? "Terminal identifier unavailable" : nil
        let project = session.projectName.isEmpty ? session.title : session.projectName
        focusAccessibilityLabel = "Focus Terminal for \(project)"
    }
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
    var bucket: AgentBucket = .active
    let actions: AgentCardActions
    @State private var hovering = false

    private var genuineApproval: Bool {
        session.hasLiveApproval && session.approval?.state == .pending
            && actions.approve != nil && actions.deny != nil
    }
    private var fellBack: Bool { session.approval?.state == .fellBack }
    private var deliveryState: PendingApproval.ResponseState? { session.approval?.state }
    private var presentation: AgentCardPresentation {
        AgentCardPresentation(session: session, bucket: bucket)
    }

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
            else if deliveryState == .sending { statusRow(presentation.deliveryLabel ?? "Sending…", "arrow.up.circle", DesignTokens.Palette.secondaryText) }
            else if deliveryState == .sent || deliveryState == .providerOutputClosed || deliveryState == .helperTerminated || deliveryState == .helperExited { statusRow(presentation.deliveryLabel ?? "Sent", "paperplane.fill", DesignTokens.Palette.secondaryText) }
            else if deliveryState == .delivered { statusRow(presentation.deliveryLabel ?? "Continued", "checkmark.circle.fill", DesignTokens.Palette.statusSuccess) }
            else if deliveryState == .deliveryFailed { statusRow("Delivery failed — answer in Terminal", "exclamationmark.triangle.fill", DesignTokens.Palette.statusFailure) }
            else if deliveryState == .expired { statusRow("No longer actionable in NotchDeck", "clock.badge.xmark", DesignTokens.Palette.tertiaryText) }
            else if fellBack { waitingInTerminalRow }
            if session.queuedApprovalCount > 0 {
                Label("\(session.queuedApprovalCount) more permission request\(session.queuedApprovalCount == 1 ? "" : "s") waiting",
                      systemImage: "list.bullet")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .accessibilityLabel("\(session.queuedApprovalCount) additional permission request\(session.queuedApprovalCount == 1 ? "" : "s") waiting")
            }
        }
        .padding(11)
        .background(hovering ? DesignTokens.Palette.cardFillHover : DesignTokens.Palette.cardFill,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: genuineApproval ? 1.4 : 0.6))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentProviderLogo(session: session, size: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName.isEmpty ? session.title : session.projectName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.primaryText).lineLimit(1)
                    LifecycleBadge(label: presentation.lifecycleLabel, active: bucket == .active)
                }
                Text(presentation.statusLine)
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText).lineLimit(1)
                if showPreview, let summary = presentation.preview {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(maxPreviewLines)
                        .truncationMode(.middle)
                }
                if let notice = presentation.terminalNotice {
                    Label(notice, systemImage: "questionmark.circle")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.Palette.statusAttention)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
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
        .accessibilityLabel(presentation.focusAccessibilityLabel)
        .accessibilityHint(session.terminalTTY == nil
            ? "Terminal identifier unavailable"
            : "Selects the existing matching Terminal tab")
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
                .accessibilityLabel("More actions for \(session.projectName.isEmpty ? session.title : session.projectName)")
        }
    }

    // MARK: Approval

    private var approvalRow: some View {
        assert(session.approval?.rawEventName == "PermissionRequest",
               "Approval card without a PermissionRequest-backed transaction")
        return VStack(alignment: .leading, spacing: 6) {
            if let tool = session.approval?.toolName, !tool.isEmpty {
                Text("Tool: \(tool)").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.primaryText).lineLimit(1)
            }
            HStack(spacing: 8) {
                if let deadline = session.approval?.fallbackDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(
                            "Available \(secondsRemaining(deadline, now: context.date))s",
                            systemImage: "timer"
                        )
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.Palette.statusAttention)
                        .accessibilityLabel(
                            "Available in NotchDeck for \(secondsRemaining(deadline, now: context.date)) seconds; Terminal is also available"
                        )
                    }
                }
                Spacer(minLength: 0)
                if approvalSending {
                    Label("Sending…", systemImage: "arrow.up.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                } else {
                    decisionButton("Deny", "xmark", DesignTokens.Palette.statusFailure,
                                   accessibilityVerb: "Deny", actions.deny)
                    decisionButton("Allow", "checkmark", DesignTokens.Palette.statusSuccess,
                                   accessibilityVerb: "Allow", actions.approve)
                }
            }
        }
    }

    private var waitingInTerminalRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.forward")
            VStack(alignment: .leading, spacing: 1) {
                Text("Respond in Terminal")
                Text("No longer actionable in NotchDeck")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Palette.statusAttention)
    }

    private func decisionButton(_ title: String, _ icon: String, _ tint: Color,
                                accessibilityVerb: String,
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
        .accessibilityLabel(
            "\(accessibilityVerb) \(session.appearance.displayName) permission for \(session.projectName.isEmpty ? session.title : session.projectName)"
        )
    }

    private func secondsRemaining(_ deadline: Date, now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    private var borderColor: Color {
        if genuineApproval { return DesignTokens.Palette.statusApproval }
        return DesignTokens.Palette.hairline
    }
}

/// Lifecycle chip. Activity is spoken once in the semantic provider line.
struct LifecycleBadge: View {
    let label: String
    let active: Bool
    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background((active ? DesignTokens.Palette.statusRunning
                                : DesignTokens.Palette.statusIdle).opacity(0.18), in: Capsule())
            .foregroundStyle(active ? DesignTokens.Palette.statusRunning
                                    : DesignTokens.Palette.statusIdle)
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

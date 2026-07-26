import SwiftUI

/// Focus Mode for a module: a back button + the module's full focused view.
/// Uses most of the panel, never pins, and preserves module state (services
/// keep their data) when returning to Home.
struct FocusContainer: View {
    let moduleID: String
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            FocusBackBar(title: registry.module(id: moduleID)?.displayName ?? "Module") {
                appState.clearFocus()
            }
            if let module = registry.module(id: moduleID) {
                module.makeFocusView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Text("Module unavailable").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Slim back bar used by all focus views.
struct FocusBackBar: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Home").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// Focus Mode for a single agent session.
struct AgentFocusContainer: View {
    @EnvironmentObject private var store: AgentSessionStore
    @EnvironmentObject private var coordinator: AgentCoordinator
    @EnvironmentObject private var appState: AppState

    private var session: AgentSession? {
        appState.focusedAgentID.flatMap { store.session(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FocusBackBar(title: session?.title ?? "Agent") { appState.clearFocus() }
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        AgentSessionCard(session: session,
                                         approvalSending: coordinator.approvalInFlight.contains(session.id),
                                         actions: focusActions(session))
                        if let summary = session.latestSummary {
                            Text(summary).font(.callout)
                                .foregroundStyle(DesignTokens.Palette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Label(session.connectivity == .connected ? "Connected session" :
                                (session.connectivity == .external ? "External window" : "Offline"),
                              systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(DesignTokens.Metrics.contentPadding)
                }
            } else {
                Text("Session ended").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func focusActions(_ session: AgentSession) -> AgentCardActions {
        let canDecide = session.hasLiveApproval
            && session.approval?.state == .pending
            && (session.approval?.handlingMode.showsFunctionalDecision ?? false)
            && (session.isBridgeConnected || session.isManaged)
        return AgentCardActions(
            focusTerminal: { coordinator.focusTerminal(session) },
            openProject: { coordinator.openProject(session) },
            approve: canDecide ? { Task { await coordinator.decide(session: session, allow: true) } } : nil,
            deny: canDecide ? { Task { await coordinator.decide(session: session, allow: false) } } : nil,
            resume: session.isManaged ? { Task { await coordinator.resume(sessionID: session.id) } } : nil,
            interrupt: session.isManaged ? { Task { await coordinator.interrupt(sessionID: session.id) } } : nil,
            followUp: nil)
    }
}

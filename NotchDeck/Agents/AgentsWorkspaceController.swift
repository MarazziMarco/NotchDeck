import Foundation
import Combine

/// Connects the Agents module's single enablement state to the real lifecycle of
/// the agent runtime. It is the ONE place that starts/stops agent runtime work,
/// so no unrelated view toggles services.
///
/// Lifecycle policy (conservative):
/// - Installed hooks, backups and persisted session data are NEVER touched here.
/// - Enabled: run terminal-presence + external-window monitoring, mark the bridge
///   UI-available, and (if a terminal integration is installed) ensure the hook
///   socket is listening. `bridge.start()` and the monitoring starters are
///   idempotent, so repeated enables create no duplicate listeners.
/// - Disabled: stop monitoring and suppress compact activity, but KEEP the hook
///   socket listening as a minimal responder that immediately releases incoming
///   synchronous permission requests to the native terminal prompt — so a hook
///   can never hang waiting for an absent UI.
@MainActor
final class AgentsWorkspaceController {
    private let settings: SettingsStore
    private let agents: AgentCoordinator
    private let store: AgentSessionStore
    private let bridge: TerminalAgentBridge
    private var cancellable: AnyCancellable?
    private var lastApplied: Bool?

    init(settings: SettingsStore, agents: AgentCoordinator,
         store: AgentSessionStore, bridge: TerminalAgentBridge) {
        self.settings = settings
        self.agents = agents
        self.store = store
        self.bridge = bridge
    }

    /// Begin observing enablement and apply the initial state exactly once.
    func start() {
        apply(settings.agentsEnabled, initial: true)
        cancellable = settings.$settings
            .map { AgentsModule.isEnabled($0) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.apply(enabled, initial: false) }
    }

    private func apply(_ enabled: Bool, initial: Bool) {
        guard lastApplied != enabled else { return }   // no duplicate transitions
        lastApplied = enabled

        store.compactSuppressed = !enabled
        Task { await bridge.setUIAvailable(enabled) }

        // The hook socket runs whenever a terminal integration is installed,
        // regardless of the module toggle, so synchronous hooks are always
        // answered (with the native fallback while the UI is disabled).
        let s = settings.settings
        if s.codexTerminalIntegration || s.claudeTerminalIntegration {
            Task { await bridge.start() }   // idempotent
        }

        if enabled {
            agents.startExternalMonitoring()          // idempotent (cancels prior)
            agents.startTerminalPresenceMonitoring()  // idempotent (cancels prior)
        } else {
            agents.stopExternalMonitoring()
            agents.stopTerminalPresenceMonitoring()
        }
    }
}

import Foundation
import Combine

/// Connects the Agents module's single enablement state to monitoring and UI
/// availability. The bridge socket itself is an app lifecycle invariant owned
/// by AppDelegate, so no preference or view can suppress bootstrap.
///
/// Lifecycle policy (conservative):
/// - Installed hooks, backups and persisted session data are NEVER touched here.
/// - Enabled: run process, terminal-presence and external-window monitoring and
///   mark the bridge UI-available.
/// - Disabled: stop monitoring and suppress compact activity. AppDelegate keeps
///   the hook socket listening as a minimal responder that immediately releases incoming
///   synchronous permission requests to the native terminal prompt — so a hook
///   can never hang waiting for an absent UI.
@MainActor
final class AgentsWorkspaceController {
    private struct BridgeConfiguration: Equatable {
        let mode: AgentPermissionHandlingMode
        let fallbackDelay: TimeInterval
        let approvalLifetime: TimeInterval
    }
    private struct CompactConfiguration: Equatable {
        let display: CompactAgentsDisplay
        let accent: AgentCompactAccent
    }

    private let settings: SettingsStore
    private let agents: AgentCoordinator
    private let store: AgentSessionStore
    private let bridge: TerminalAgentBridge
    private var cancellables = Set<AnyCancellable>()
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
        settings.$settings
            .map { AgentsModule.isEnabled($0) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.apply(enabled, initial: false) }
            .store(in: &cancellables)

        settings.$settings
            .map {
                BridgeConfiguration(
                    mode: $0.agentPermissionHandlingMode,
                    fallbackDelay: $0.terminalFallbackDelay.seconds,
                    approvalLifetime: $0.approvalAvailability.seconds
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] configuration in
                guard let self else { return }
                Task {
                    await self.bridge.configure(
                        mode: configuration.mode,
                        fallbackDelay: configuration.fallbackDelay,
                        approvalLifetime: configuration.approvalLifetime
                    )
                }
            }
            .store(in: &cancellables)

        settings.$settings
            .map {
                CompactConfiguration(
                    display: $0.compactAgentsDisplay,
                    accent: $0.agentCompactAccent
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] configuration in
                self?.store.compactDisplay = configuration.display
                self?.store.compactAccent = configuration.accent
            }
            .store(in: &cancellables)
    }

    private func apply(_ enabled: Bool, initial: Bool) {
        guard lastApplied != enabled else { return }   // no duplicate transitions
        lastApplied = enabled

        store.compactSuppressed = !enabled

        // Configure handling and UI availability only. Socket bootstrap is
        // unconditional and belongs to AppDelegate.
        let s = settings.settings
        Task {
            await bridge.configure(
                mode: s.agentPermissionHandlingMode,
                fallbackDelay: s.terminalFallbackDelay.seconds,
                approvalLifetime: s.approvalAvailability.seconds
            )
            await bridge.setUIAvailable(enabled)
        }

        if enabled {
            agents.startProcessDiscovery()             // authoritative liveness
            agents.startExternalMonitoring()          // idempotent (cancels prior)
            agents.startTerminalPresenceMonitoring()  // idempotent (cancels prior)
        } else {
            agents.stopProcessDiscovery()
            agents.stopExternalMonitoring()
            agents.stopTerminalPresenceMonitoring()
        }
    }
}

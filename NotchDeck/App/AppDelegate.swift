import AppKit
import SwiftUI
import Combine

/// Sets up the notch panel, interaction monitors and app-wide services. Keeps
/// the app out of the Dock (accessory activation policy) while the menu bar item
/// and panel drive the UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var interaction: NotchInteractionCoordinator?
    private var hotkeys: GlobalHotkeyMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var knownApprovalIDs = Set<UUID>()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        AppEnvironment.shared = environment

        // Socket availability is an application lifecycle invariant, independent
        // of installed-hook preference flags and independent of every view.
        Task { await environment.terminalBridge.start() }
        Task.detached {
            do {
                _ = try HookInstaller.ensureHelperInstalled(force: false)
            } catch {
                Log.agents.error("helper bootstrap failed: \(error.localizedDescription)")
            }
        }

        // Dock icon hidden by default; a diagnostics toggle can show it.
        NSApp.setActivationPolicy(environment.settings.settings.showDockIcon ? .regular : .accessory)

        environment.diagnostics.enabled = environment.settings.settings.interactionDiagnostics
        environment.pointerTracker.start()

        let controller = NotchPanelController(environment: environment)
        self.panelController = controller

        let interaction = NotchInteractionCoordinator(
            appState: environment.appState,
            settings: environment.settings,
            tracker: environment.pointerTracker,
            diagnostics: environment.diagnostics)
        interaction.start()
        self.interaction = interaction
        environment.interaction = interaction

        let hotkeys = GlobalHotkeyMonitor(appState: environment.appState)
        hotkeys.start()
        self.hotkeys = hotkeys

        // Wire the terminal bridge into the coordinator. The workspace owns
        // process/window monitoring and UI availability; AppDelegate owns the
        // socket lifecycle above.
        environment.agents.terminalBridge = environment.terminalBridge
        environment.agentsWorkspace.start()

        Task {
            await environment.permissions.refresh()
            await environment.agents.refreshAvailability()
        }

        // Auto-open the notch (without stealing focus) when a session newly needs
        // approval, if enabled. App-wide so it works even while collapsed.
        environment.agentStore.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self, weak environment] sessions in
                guard let self, let environment,
                      environment.settings.agentsEnabled,
                      environment.settings.settings.autoOpenOnApproval else { return }
                let approvals = Set(sessions.filter { $0.status == .waitingForApproval }.map(\.id))
                let fresh = approvals.subtracting(self.knownApprovalIDs)
                self.knownApprovalIDs = approvals
                if !fresh.isEmpty, !environment.appState.isExpanded {
                    environment.appState.expand(face: .agents)
                }
            }
            .store(in: &cancellables)

        if !environment.settings.settings.onboardingCompleted {
            OnboardingWindowPresenter.shared.show(environment: environment)
        }
        // First-launch permission onboarding as a normal centred window (collapses
        // the notch first so system dialogs never hide behind the panel).
        if !environment.settings.settings.permissionsSetupCompleted {
            PermissionsSetupWindow.shared.show(environment: environment)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared?.handleQuit()
        }
        interaction?.stop()
        hotkeys?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

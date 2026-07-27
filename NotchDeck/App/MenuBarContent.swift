import SwiftUI

/// Contents of the menu-bar item. Reads the shared environment set at launch.
struct MenuBarContent: View {
    private var env: AppEnvironment? { AppEnvironment.shared }

    var body: some View {
        Group {
            Button("Open NotchDeck") { env?.appState.expand() }
            Button("Utilities Face") { env?.appState.expand(face: .utilities) }
            Button("Agents Face") { env?.appState.expand(face: .agents) }
            Divider()
            Button(clipboardPaused ? "Resume Clipboard" : "Pause Clipboard") { toggleClipboard() }
            Button("New Agent Session…") { newSession() }
            Divider()
            Button("Settings…") { SettingsWindowPresenter.shared.show() }
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
            Divider()
            Button("Quit NotchDeck") {
                ApplicationTerminationCoordinator.shared.requestTermination()
            }
        }
    }

    private var clipboardPaused: Bool { env?.settings.settings.clipboardMonitoringPaused ?? false }

    private func toggleClipboard() {
        guard let env else { return }
        let paused = !env.settings.settings.clipboardMonitoringPaused
        env.settings.settings.clipboardMonitoringPaused = paused
        env.clipboard.isPaused = paused
        if paused { env.clipboard.stopMonitoring() } else { env.clipboard.startMonitoring() }
    }

    private func newSession() {
        env?.appState.expand(face: .agents)
        SettingsWindowPresenter.shared.hide()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { env?.settings.settings.launchAtLogin ?? false },
            set: { newValue in
                env?.settings.settings.launchAtLogin = newValue
                LoginItemService.setEnabled(newValue)
            })
    }
}

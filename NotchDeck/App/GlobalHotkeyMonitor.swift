import AppKit

/// Minimal global hotkey handling for face switching and toggling the panel.
/// Uses a local + global monitor for a configurable modifier chord. Kept simple
/// (no Carbon hotkey registration) to avoid private/legacy APIs.
@MainActor
final class GlobalHotkeyMonitor {
    private let appState: AppState
    private var monitor: Any?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            // ⌃⌥ + Left/Right switches faces; ⌃⌥N toggles the panel.
            let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
            guard mods == [.control, .option] else { return event }
            switch event.keyCode {
            case 123: self.appState.toggleFace(to: .utilities); return nil // ←
            case 124: self.appState.toggleFace(to: .agents); return nil     // →
            case 45:  self.toggle(); return nil                             // N
            default:  return event
            }
        }
    }

    private func toggle() {
        if appState.isExpanded { appState.compact() } else { appState.expand() }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

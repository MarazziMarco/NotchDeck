import AppKit
import SwiftUI

/// Presents the Permissions Setup as a normal centred window. Collapses the notch
/// panel first and activates NotchDeck so system permission dialogs are not
/// hidden behind the expanded panel.
@MainActor
final class PermissionsSetupWindow {
    static let shared = PermissionsSetupWindow()
    private var window: NSWindow?

    func show(environment: AppEnvironment) {
        // 1. Collapse / hide the expanded notch so it never covers a system dialog.
        environment.appState.setPinnedByUser(false, reason: "permissions setup")
        environment.appState.compact()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = PermissionsSetupModel(settings: environment.settings)
        let root = environment.inject(PermissionsSetupView(model: model) { [weak self] in
            self?.window?.close()
            self?.window = nil
        })
        let hosting = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchDeck Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.isReleasedWhenClosed = false
        window.level = .floating          // above ordinary app content
        window.center()
        self.window = window

        // 2. Bring NotchDeck + the window to the front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // 3. Re-check statuses whenever the app becomes active (e.g. after the user
        //    changed a setting in System Settings).
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated { model?.refreshAll() }
        }
    }
}

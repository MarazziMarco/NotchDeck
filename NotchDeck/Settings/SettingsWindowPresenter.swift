import AppKit
import SwiftUI

/// Presents the Settings window as a standard, focusable `NSWindow` hosting
/// SwiftUI. Kept separate from the borderless notch panel so text fields and
/// standard window chrome behave normally. Acts as its own window delegate so it
/// can clear the notch's secondary-window flag on close.
@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?

    func show() {
        guard let env = AppEnvironment.shared else { return }
        // Prepare the notch: cancel hover, unpin, collapse, suspend reopen.
        env.interaction?.prepareForSecondaryWindow()

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let root = env.inject(SettingsRootView())
        let hosting = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchDeck Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        AppEnvironment.shared?.interaction?.secondaryWindowDidClose()
    }

    func windowWillClose(_ notification: Notification) {
        AppEnvironment.shared?.interaction?.secondaryWindowDidClose()
    }
}

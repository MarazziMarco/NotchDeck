import AppKit
import SwiftUI

/// Presents the short first-run onboarding as a modal-ish standard window.
@MainActor
final class OnboardingWindowPresenter {
    static let shared = OnboardingWindowPresenter()
    private var window: NSWindow?

    func show(environment: AppEnvironment) {
        if window != nil { return }
        let root = environment.inject(OnboardingView { [weak self] in
            environment.settings.settings.onboardingCompleted = true
            self?.window?.close()
            self?.window = nil
        })
        let hosting = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to NotchDeck"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

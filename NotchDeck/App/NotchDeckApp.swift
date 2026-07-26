import SwiftUI

/// App entry. A menu-bar-only (LSUIElement) app: the notch panel is managed by
/// `AppDelegate`; the single SwiftUI scene is the menu bar item.
@main
struct NotchDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            // Separate monochrome template mark (not the full-colour app icon).
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.menu)
    }
}

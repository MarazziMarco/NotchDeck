import AppKit

/// Borderless, transparent panel that hosts the notch UI. It floats above normal
/// windows, joins all Spaces, stays out of the Dock and window cycle, and only
/// becomes key when it actually needs text input (search / prompts).
final class NotchPanel: NSPanel {

    /// When true the panel is allowed to become key (for text fields). In the
    /// compact state this is false so we never steal focus.
    var allowsKeyFocus: Bool = false {
        didSet { if !allowsKeyFocus, isKeyWindow { resignKeyIfPossible() } }
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .statusBar          // above normal windows, below menu-bar menus
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false           // shadow is drawn by SwiftUI for precise control
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Mouse movement must keep flowing through the nonactivating panel so
        // its visible controls become interactive before the first click.
        acceptsMouseMovedEvents = true

        // Visible across every Space and over full-screen apps where allowed.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Not in the Dock / window menu.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }

    /// True while the panel actually holds key focus (e.g. a text field is being
    /// edited). The watchdog checks this so it never collapses mid-input.
    var allowsKeyFocusInUse: Bool { isKeyWindow }

    private func resignKeyIfPossible() {
        // Hand key status back so we don't hold focus in compact state.
        resignKey()
    }
}

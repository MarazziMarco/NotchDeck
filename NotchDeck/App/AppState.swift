import AppKit
import Combine

/// Central navigation + presentation state for the notch. Owns the state
/// machine and publishes derived values the panel/views observe.
///
/// Pin/keep-open is modelled with explicit, single-purpose flags so nothing can
/// pin the panel as a side effect. `isPinnedByUser` is the ONLY sticky keep-open
/// signal and may only be toggled by the dedicated Pin button (via
/// `setPinnedByUser`). Everything else that should keep the panel open while it
/// is happening (pointer inside, drag, text editing, a secondary window) is a
/// transient condition, not a pin.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var presentation: NotchPresentationState = .compact
    @Published private(set) var face: NotchFace = .utilities

    /// The ONLY sticky keep-open state. Toggled solely by the Pin button.
    @Published private(set) var isPinnedByUser: Bool = false

    // Transient keep-open conditions (never pin).
    @Published var isPointerInside: Bool = false
    @Published var isDragging: Bool = false
    @Published var isEditing: Bool = false
    @Published var isSecondaryWindowOpen: Bool = false
    /// Widget customization keeps the panel open (never pins).
    @Published var isCustomizingDashboard: Bool = false

    /// Set briefly when a Pomodoro/timer finishes, for the compact status.
    @Published var timerJustFinished: Bool = false

    /// Focus Mode: when set, the expanded panel shows this module's full view
    /// instead of the Home dashboard. Focus never pins.
    @Published var focusedModuleID: String?
    /// Agent Focus Mode.
    @Published var focusedAgentID: UUID?
    /// Module library overlay visibility.
    @Published var showingModuleLibrary = false

    func focusModule(_ id: String) { focusedModuleID = id; showingModuleLibrary = false }
    func focusAgent(_ id: UUID) { focusedAgentID = id }
    func clearFocus() { focusedModuleID = nil; focusedAgentID = nil }

    private var machine = NotchStateMachine()
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.face = settings.settings.defaultFace
        machine.switchFace(to: settings.settings.defaultFace)
    }

    var reduceMotion: Bool {
        settings.settings.reduceMotionOverride
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var isExpanded: Bool { presentation == .expanded }

    /// Backwards-compatible alias used by drop handling / compact status.
    var dragInProgress: Bool {
        get { isDragging }
        set { isDragging = newValue }
    }

    /// True when any condition should keep the expanded panel alive.
    var shouldStayOpen: Bool {
        isPinnedByUser || isPointerInside || isDragging || isEditing
            || isSecondaryWindowOpen || isCustomizingDashboard
    }

    // MARK: Pin — the single, audited mutator

    /// The ONLY path that mutates `isPinnedByUser`. Every call names its reason so
    /// stray pins are traceable in diagnostics.
    func setPinnedByUser(_ pinned: Bool, reason: StaticString) {
        guard pinned != isPinnedByUser else { return }
        isPinnedByUser = pinned
        #if DEBUG
        Log.panel.debug("isPinnedByUser -> \(pinned, privacy: .public) [\(reason)]")
        #endif
    }

    // MARK: Navigation

    func handle(_ event: NotchEvent) {
        let changed = machine.apply(event)
        if changed { sync() }
    }

    func expand(face: NotchFace? = nil) {
        machine.apply(.requestExpand(face))
        sync()
    }

    func compact() {
        machine.apply(.requestCompact)
        // Collapsing returns to Home next time; module STATE is preserved by the
        // services, only the navigation resets.
        focusedModuleID = nil
        focusedAgentID = nil
        showingModuleLibrary = false
        sync()
    }

    func toggleFace(to target: NotchFace? = nil) {
        if machine.switchFace(to: target) {
            sync()
            settings.settings.defaultFace = machine.face
        }
    }

    private func sync() {
        presentation = machine.presentation
        face = machine.face
    }
}

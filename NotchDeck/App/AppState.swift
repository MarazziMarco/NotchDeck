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

    /// Single authoritative UI flag for whether the Agents workspace is enabled.
    /// Views read THIS instead of re-deriving the check, so the enabled/disabled
    /// behaviour lives in one place. Mirrors `AppSettings.moduleEnabled`.
    @Published private(set) var agentsEnabled: Bool = true

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
    /// Module library overlay visibility.
    @Published var showingModuleLibrary = false

    func focusModule(_ id: String) { focusedModuleID = id; showingModuleLibrary = false }
    func clearFocus() { focusedModuleID = nil }

    private var machine = NotchStateMachine()
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore) {
        self.settings = settings
        self.agentsEnabled = settings.agentsEnabled
        // Normalise a persisted `.agents` selection to `.utilities` when Agents is
        // disabled, so no hidden Agents content is ever mounted.
        let start = settings.agentsEnabled ? settings.settings.defaultFace : .utilities
        self.face = start
        machine.switchFace(to: start)

        // React to Agents being enabled/disabled from Settings → Modules. This is
        // the ONLY place the face is normalised, keeping the rule in one spot.
        // @Published fires synchronously with the new value, so the face is
        // normalised in the same runloop tick the toggle happens — no flash of
        // Agents content and deterministic for tests.
        settings.$settings
            .map { AgentsModule.isEnabled($0) }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyAgentsEnabled(enabled) }
            .store(in: &cancellables)
    }

    /// Apply an Agents enable/disable transition. Disabling while Agents is the
    /// current face switches to Utilities immediately and drops any agent focus.
    /// Re-enabling never switches away from Utilities.
    private func applyAgentsEnabled(_ enabled: Bool) {
        agentsEnabled = enabled
        guard !enabled else { return }
        // Do NOT persist `defaultFace` here: writing settings from inside its own
        // change notification re-enters the publisher with a pre-commit value. It
        // is unnecessary anyway — `init` re-normalises a persisted `.agents` to
        // `.utilities` whenever Agents is disabled.
        if machine.switchFace(to: .utilities) { sync() }
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
        showingModuleLibrary = false
        sync()
    }

    func toggleFace(to target: NotchFace? = nil) {
        // Agents is unreachable while disabled (no switcher, swipe ignored).
        if !agentsEnabled, (target ?? face.toggled) == .agents { return }
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

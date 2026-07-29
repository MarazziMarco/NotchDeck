import AppKit
import Combine

/// Turns pointer/keyboard activity into notch state changes. Movement/inclusion
/// comes from `PointerTrackingService` (screen-rect based, reliable across frame
/// changes); this type owns the decisions, delays, pin logic and the
/// suspend-reopen guard used when a secondary window (Settings) opens.
@MainActor
final class NotchInteractionCoordinator {
    private let appState: AppState
    private let settings: SettingsStore
    private let tracker: PointerTrackingService
    private let diagnostics: NotchDiagnostics

    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    /// While true, hover cannot reopen the panel. Cleared once the pointer has
    /// left the activation area (so Settings closing doesn't instantly reopen).
    private var suspendReopen = false

    init(appState: AppState, settings: SettingsStore,
         tracker: PointerTrackingService, diagnostics: NotchDiagnostics) {
        self.appState = appState
        self.settings = settings
        self.tracker = tracker
        self.diagnostics = diagnostics
    }

    func start() {
        tracker.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in self?.handle(snap) }
            .store(in: &cancellables)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) {
            [weak self] event in self?.handleLocal(event) ?? event
        }
    }

    func stop() {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
        openTask?.cancel(); closeTask?.cancel()
        cancellables.removeAll()
    }

    /// Called before showing Settings or any other secondary window: cancel
    /// pending hover work, UNPIN, force compact, and suspend hover reopen until
    /// the pointer leaves the notch.
    func prepareForSecondaryWindow() {
        openTask?.cancel(); openTask = nil
        closeTask?.cancel(); closeTask = nil
        suspendReopen = true
        appState.isSecondaryWindowOpen = true
        appState.setPinnedByUser(false, reason: "secondary window opened")
        appState.compact()
        diagnostics.noteClose("secondary window opened")
    }

    /// Called when a secondary window closes.
    func secondaryWindowDidClose() {
        appState.isSecondaryWindowOpen = false
    }

    // MARK: Snapshot handling

    private func handle(_ snap: PointerSnapshot) {
        diagnostics.pointerLocation = snap.location
        appState.isPointerInside = snap.insideAny

        // Re-arm hover once the pointer has genuinely left the activation area.
        if suspendReopen && !snap.insideAny {
            suspendReopen = false
        }

        if snap.insideAny {
            // Inside the notch or expanded panel: never close.
            if closeTask != nil { closeTask?.cancel(); closeTask = nil }
            guard settings.settings.hoverToOpen, !suspendReopen else { return }
            if appState.presentation == .compact {
                scheduleOpen(reason: "hover-enter")
            }
        } else {
            // Outside both zones.
            openTask?.cancel(); openTask = nil
            // Collapse unless a genuine keep-open condition holds. Pomodoro
            // running is NOT such a condition.
            if appState.isExpanded, !appState.shouldStayOpen {
                scheduleClose(reason: "hover-exit")
            }
        }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 53: // Escape
            if appState.isExpanded {
                appState.setPinnedByUser(false, reason: "escape")
                appState.handle(.escapePressed)
                diagnostics.noteClose("escape")
                return nil
            }
        case .leftMouseDown:
            // Clicks NEVER pin. A click on the compact notch opens it; a click
            // outside an unpinned expanded panel dismisses it. Pinning is done
            // exclusively by the Pin button (a SwiftUI Button that consumes its
            // own tap, so it never reaches this monitor as a background click).
            let inside = tracker.snapshot.insideInteractiveSurface
            if inside {
                if appState.presentation == .compact {
                    appState.expand()
                    diagnostics.noteOpen("click-open")
                }
            } else if appState.isExpanded, !appState.isPinnedByUser, !appState.isEditing {
                appState.compact()
                appState.setPinnedByUser(false, reason: "outside-click")
                diagnostics.noteClose("outside-click")
            }
        default:
            break
        }
        return event
    }

    // MARK: Delays

    private func scheduleOpen(reason: String) {
        openTask?.cancel()
        let delay = settings.settings.openDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.tracker.snapshot.insideAny, !self.suspendReopen,
                  self.appState.presentation == .compact else { return }
            self.appState.expand()
            self.diagnostics.noteOpen(reason)
        }
    }

    private func scheduleClose(reason: String) {
        closeTask?.cancel()
        let delay = settings.settings.closeDelay
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard !self.tracker.snapshot.insideAny, !self.appState.shouldStayOpen,
                  self.appState.isExpanded else { return }
            self.appState.compact()
            self.diagnostics.noteClose(reason)
        }
    }
}

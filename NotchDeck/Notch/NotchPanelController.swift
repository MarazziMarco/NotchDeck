import AppKit
import SwiftUI
import Combine

/// Owns the `NotchPanel`, hosts the SwiftUI content, keeps the panel's frame in
/// sync with the notch geometry and presentation state, feeds screen-coordinate
/// hot zones to the pointer tracker, and runs a watchdog that re-collapses a
/// panel left "expanded" while the pointer is elsewhere and it isn't pinned.
@MainActor
final class NotchPanelController {
    private let panel: NotchPanel
    private let environment: AppEnvironment
    private var hostingView: NSHostingView<AnyView>!
    private var cancellables = Set<AnyCancellable>()
    private var watchdog: Timer?

    private var tracker: PointerTrackingService { environment.pointerTracker }
    private var diagnostics: NotchDiagnostics { environment.diagnostics }

    init(environment: AppEnvironment) {
        self.environment = environment
        let initialFrame = NSRect(x: 0, y: 0, width: 200, height: 40)
        self.panel = NotchPanel(contentRect: initialFrame)

        let root = environment.inject(NotchRootView())
        hostingView = NSHostingView(rootView: AnyView(root))
        // Grey-corner fix at the composition level: the hosting view and its layer
        // must be fully transparent so nothing rectangular is painted outside the
        // SwiftUI rounded mask. The panel itself is already clear + non-opaque.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        if #available(macOS 13.0, *) { hostingView.sizingOptions = [] }
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        #if DEBUG
        // Inspection mode: tint the panel + hosting backgrounds so any pixel
        // outside the rounded mask is obvious. Off unless the env var is set.
        if ProcessInfo.processInfo.environment["NOTCHDECK_INSPECT_PANEL"] == "1" {
            panel.backgroundColor = NSColor.systemPink.withAlphaComponent(0.35)
            hostingView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.35).cgColor
        }
        #endif

        observe()
        reposition(animated: false)
        panel.orderFrontRegardless()
        startWatchdog()
    }

    private func observe() {
        Publishers.CombineLatest(environment.appState.$presentation, environment.appState.$face)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reposition(animated: true) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition(animated: false) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.environment.appState.compact() }  // reset on topology change
            .store(in: &cancellables)

        environment.settings.$settings
            .map(\.monitorSelection)
            .removeDuplicates()
            .sink { [weak self] _ in self?.reposition(animated: false) }
            .store(in: &cancellables)

        // Panel holding key focus == a text field is being edited. Track it so
        // the close logic / watchdog keep the panel open while typing.
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] note in
                guard let self, note.object as? NSWindow === self.panel else { return }
                self.environment.appState.isEditing = true
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] note in
                guard let self, note.object as? NSWindow === self.panel else { return }
                self.environment.appState.isEditing = false
            }
            .store(in: &cancellables)

        // Re-position when the live-activity layout changes so the compact strip
        // widens/narrows to fit (e.g. timer + agents together).
        environment.liveActivity.$layout
            .map { ($0.leading != nil ? 1 : 0) + ($0.trailing != nil ? 1 : 0) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition(animated: true) }
            .store(in: &cancellables)

        // Animate the panel between per-tab content heights and widths.
        environment.responsive.$utilitiesContentHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                if self?.environment.appState.isExpanded == true { self?.reposition(animated: true) }
            }
            .store(in: &cancellables)
        environment.responsive.$utilitiesTab
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                if self?.environment.appState.isExpanded == true { self?.reposition(animated: true) }
            }
            .store(in: &cancellables)
    }

    private func currentMetrics() -> DisplayMetrics? {
        let preferMouse = environment.settings.settings.monitorSelection == .followMouse
        guard let screen = NotchGeometryService.targetScreen(preferMouse: preferMouse) else {
            return nil
        }
        return NotchGeometryService.metrics(for: screen)
    }

    /// Compute + publish the responsive layout for the current target screen.
    @discardableResult
    private func updateResponsive(for screen: NSScreen) -> NotchResponsiveLayout {
        let geo = ScreenGeometry.from(screen)
        let s = environment.settings.settings
        let prefs = NotchResponsiveLayoutService.Preferences(
            width: s.panelWidthPreference,
            density: s.dashboardDensity,
            tabLabels: s.tabLabelMode,
            maxHomeModules: s.maxHomeModulesPreference)
        let access = AccessibilityLayoutPreferences(
            largeText: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: environment.appState.reduceMotion)
        let tab = environment.appState.face == .utilities ? environment.responsive.utilitiesTab : nil
        let layout = NotchResponsiveLayoutService.compute(
            screen: geo, face: environment.appState.face, prefs: prefs, accessibility: access, tab: tab)
        if environment.responsive.current != layout { environment.responsive.current = layout }
        return layout
    }

    private func targetScreen() -> NSScreen? {
        let preferMouse = environment.settings.settings.monitorSelection == .followMouse
            || environment.settings.settings.followActiveDisplay
        return NotchGeometryService.targetScreen(preferMouse: preferMouse)
    }

    /// Extra compact-strip width for live activities. Two wings need more room
    /// than one; nothing active stays notch-tight.
    private func compactExtraWidth() -> CGFloat {
        let l = environment.liveActivity.layout
        // Two wings need enough room that each side clears the camera housing and
        // the enlarged right-wing MM:SS (22pt "00:00" + notch-safe inset + trailing
        // padding) is never clipped or pushed under the housing. 210 → ~105pt per
        // wing on a 200pt notch (≈67pt usable after the 22+16pt insets).
        if l.leading != nil && l.trailing != nil { return 210 }
        if l.leading != nil || l.trailing != nil { return 100 }
        return 0
    }

    func reposition(animated: Bool) {
        guard let metrics = currentMetrics() else {
            Log.panel.error("No screen available to position notch panel")
            return
        }
        let state = environment.appState.presentation
        let extra = compactExtraWidth()

        // Responsive expanded sizing from actual logical screen geometry.
        let responsive = targetScreen().map { updateResponsive(for: $0) } ?? environment.responsive.current
        let geo = targetScreen().map { ScreenGeometry.from($0) }

        // Utilities uses a per-tab content height so the panel hugs its content
        // (no blank lower half); Agents keeps the responsive dashboard height.
        var contentResponsive = responsive
        if environment.appState.face == .utilities {
            contentResponsive.dashboardHeight = min(NotchResponsiveLayoutService.hardMaxHeight,
                                                    environment.responsive.utilitiesContentHeight)
        }

        // Closed & completely idle (no visible compact content) → collapse to the
        // physical notch. Any live activity → the compact capsule.
        let compactActivity = !environment.liveActivity.layout.isEmpty
        var layout = NotchGeometryService.layout(
            for: metrics,
            state: state,
            face: environment.appState.face,
            expandedContentHeight: contentResponsive.dashboardHeight,
            compactExtraWidth: extra,
            compactActivity: compactActivity)

        // Override the expanded frame with the responsive, edge-safe frame.
        if state == .expanded, let geo {
            let cHeight = NotchGeometryService.compactHeight(for: metrics)
            layout.panelFrame = NotchResponsiveLayoutService.expandedPanelFrame(
                screen: geo, layout: contentResponsive, compactHeight: cHeight)
        }

        panel.allowsKeyFocus = (state == .expanded)

        let reduceMotion = environment.appState.reduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(layout.panelFrame, display: true)
            }
        } else {
            panel.setFrame(layout.panelFrame, display: true)
        }

        // Compact panels must not intercept clicks/hover outside the notch.
        panel.ignoresMouseEvents = false
        if state == .expanded {
            panel.orderFrontRegardless()
        }

        updateHotZones(metrics: metrics, layout: layout, state: state)
        updateCompactLayoutInfo(metrics: metrics)
        updateDiagnostics(metrics: metrics, layout: layout, state: state)
    }

    /// Compute the screen-coordinate hot zones. The compact activation zone is
    /// slightly wider than the notch and extends a little below its lower edge so
    /// it's genuinely reachable by the pointer.
    private func updateHotZones(metrics: DisplayMetrics, layout: NotchLayout,
                                state: NotchPresentationState) {
        let cWidth = NotchGeometryService.compactWidth(for: metrics) + compactExtraWidth()
        // Hover/activation follows the taller compact capsule so hovering the
        // rounded ends (and the area just below) opens NotchDeck.
        let cHeight = NotchGeometryService.compactVisualHeight(for: metrics)
        let extraSide: CGFloat = 46
        let extraBelow: CGFloat = 16
        let activation = CGRect(
            x: metrics.frame.midX - cWidth / 2 - extraSide,
            y: metrics.frame.maxY - cHeight - extraBelow,
            width: cWidth + extraSide * 2,
            height: cHeight + extraBelow)

        // Expanded interaction zone: the panel frame (only when expanded), with a
        // small forgiving margin so brief pointer slips don't close it.
        let expanded = (state == .expanded)
            ? layout.panelFrame.insetBy(dx: -8, dy: -8)
            : .zero

        tracker.updateRects(compact: activation, expanded: expanded)
    }

    private func updateCompactLayoutInfo(metrics: DisplayMetrics) {
        let info = environment.notchLayout
        let idle = environment.liveActivity.layout.isEmpty && !environment.appState.isExpanded
        info.hasNotch = metrics.hasNotch
        info.physicalNotchHeight = metrics.notchHeight
        info.physicalIdle = idle
        // Idle collapses to the exact physical notch width; activity widens it.
        info.compactPanelWidth = idle
            ? NotchGeometryService.physicalIdleSize(for: metrics).width
            : NotchGeometryService.compactWidth(for: metrics) + compactExtraWidth()
        info.housingWidth = metrics.hasNotch ? metrics.notchWidth : 0
    }

    private func updateDiagnostics(metrics: DisplayMetrics, layout: NotchLayout,
                                   state: NotchPresentationState) {
        guard diagnostics.enabled else { return }
        diagnostics.compactActivationRect = tracker.compactActivationRect
        diagnostics.expandedInteractionRect = tracker.expandedInteractionRect
        diagnostics.panelFrame = panel.frame
        diagnostics.presentation = state.rawValue
        diagnostics.isPinned = environment.appState.isPinnedByUser
        diagnostics.panelVisible = panel.isVisible
        diagnostics.panelLevel = panel.level.rawValue
        diagnostics.activeScreen = "\(Int(metrics.frame.width))×\(Int(metrics.frame.height))"
        // Width diagnostics.
        let r = environment.responsive.current
        diagnostics.selectedTab = environment.appState.face == .utilities
            ? environment.settings.settings.lastUtilitiesTab : "agents"
        diagnostics.tabProfile = environment.appState.face == .utilities
            ? environment.responsive.utilitiesTab.rawValue : "agents"
        diagnostics.panelWidth = r.panelWidth
        diagnostics.availableWidth = metrics.frame.width
        diagnostics.layoutClassName = r.layoutClass.rawValue
        let usable = r.panelWidth - 16
        diagnostics.homeOneRow = !EditorialHomeLayout.requiresPaging(
            order: EditorialHomeLayout.defaultOrder,
            ratios: EditorialHomeLayout.ratios(for: r.layoutClass),
            minWidths: EditorialHomeLayout.minWidths, contentWidth: usable,
            layoutClass: r.layoutClass)

        // Compact live-activity (Pomodoro countdown) diagnostics.
        let live = environment.liveActivity.layout
        let compactW = NotchGeometryService.compactWidth(for: metrics) + compactExtraWidth()
        let compactH = NotchGeometryService.compactHeight(for: metrics)
        let housingW: CGFloat = metrics.hasNotch ? metrics.notchWidth : 0
        let wingW = max(0, (compactW - housingW) / 2)
        diagnostics.allocatedCompactWidth = compactW
        diagnostics.leftWingFrame = CGRect(x: 0, y: 0, width: wingW, height: compactH)
        diagnostics.housingFrame = CGRect(x: wingW, y: 0, width: housingW, height: compactH)
        diagnostics.rightWingFrame = CGRect(x: wingW + housingW, y: 0, width: wingW, height: compactH)
        // The MM:SS lives in the right wing when the Pomodoro spans both wings,
        // otherwise in whichever wing carries the combined slot (leading).
        let mmssWing = (live.trailing?.emphasize == true) ? diagnostics.rightWingFrame
                       : diagnostics.leftWingFrame
        diagnostics.compactTextFrame = mmssWing
        diagnostics.pomodoroRemaining = environment.pomodoro.engine.isRunning
            ? environment.pomodoro.formattedRemaining : "-"
        var parts: [String] = []
        if live.leading != nil { parts.append("L") }
        if live.trailing != nil { parts.append("R") }
        diagnostics.compactActivity = parts.isEmpty ? "none" : parts.joined(separator: "+")

        // Corner / background diagnostics — outer panel base and content mask use
        // the same rounded shape; the fill is opaque black in Deep Black / Max
        // Contrast so the lower corners never show a grey material fringe.
        let intensity = environment.settings.settings.backgroundIntensity
        diagnostics.outerClipRadius = DesignTokens.Metrics.expandedCornerRadius
        diagnostics.contentClipRadius = DesignTokens.Metrics.expandedCornerRadius
        diagnostics.backgroundLayers = intensity.usesMaterial ? "material+surface" : "opaque-black"
        diagnostics.lowerCornerFill = intensity.hasOpaqueBlackCorners ? "black" : "material(grey)"
    }

    // MARK: Watchdog

    private func startWatchdog() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStuckState() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// If the state claims expanded but the pointer is outside all zones and no
    /// keep-open condition holds (pin / drag / editing / secondary window),
    /// realign and collapse. An active Pomodoro is deliberately NOT a keep-open
    /// condition.
    private func checkStuckState() {
        let state = environment.appState
        guard state.isExpanded else { return }
        guard !state.shouldStayOpen else { return }
        guard !panel.allowsKeyFocusInUse else { return }
        if !tracker.snapshot.insideAny {
            diagnostics.noteClose("watchdog realign")
            state.compact()
        }
    }

    func makeKeyForInput() {
        guard panel.allowsKeyFocus else { return }
        panel.makeKey()
    }

    var window: NotchPanel { panel }
}

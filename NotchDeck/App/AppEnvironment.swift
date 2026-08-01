import SwiftUI
import Combine

/// Owns and wires every long-lived service. Injected into the SwiftUI
/// environment so views and modules can reach shared state without globals.
@MainActor
final class AppEnvironment: ObservableObject {
    /// Set once at launch by `AppDelegate`; read by menu-bar/settings scenes.
    static var shared: AppEnvironment!

    let settings: SettingsStore
    let appState: AppState
    let clipboard: ClipboardService
    let fileShelf: FileShelfStore
    let mirror: MirrorService
    let pomodoro: PomodoroService
    let agentStore: AgentSessionStore
    let approvalPeek: ApprovalPeekCoordinator
    let agents: AgentCoordinator
    let permissions: PermissionCoordinator
    let registry: ModuleRegistry
    let pointerTracker: PointerTrackingService
    let diagnostics: NotchDiagnostics
    let notchLayout: NotchLayoutInfo
    let responsive: NotchResponsiveLayoutService
    let dashboard: DashboardModel
    let terminalBridge: TerminalAgentBridge
    let terminalStats: TerminalBridgeStats
    /// Verified decision channel for external responders (Arcus). Peer-verified,
    /// fail-closed; maps accept/deny onto the bridge. Inert until a verified peer
    /// connects, so it is harmless when the Agents module is off.
    let agentDecisionService: AgentDecisionService
    let quickNote: QuickNoteService
    let nowPlaying: NowPlayingService
    let battery: BatteryService
    let downloads: DownloadsService
    let screenshot: ScreenshotService
    let liveActivity: LiveActivityCoordinator
    /// Community-extensible module registry (System Pulse, …).
    let community: CommunityModuleRegistry
    /// Owns the Agents runtime lifecycle driven by the module toggle.
    let agentsWorkspace: AgentsWorkspaceController
    /// Set by AppDelegate; used by secondary windows to prepare the notch.
    weak var interaction: NotchInteractionCoordinator?

    /// - mediaProvider: the Now Playing boundary. Production uses AppleScript;
    ///   tests inject a fake so constructing the environment never launches
    ///   osascript / Music.app or triggers an Automation prompt.
    init(settings: SettingsStore = SettingsStore(),
         mediaProvider: NowPlayingProviding = AppleScriptNowPlayingProvider()) {
        self.settings = settings
        let appState = AppState(settings: settings)
        self.appState = appState
        self.clipboard = ClipboardService(maxItems: settings.settings.clipboardMaxItems)
        self.fileShelf = FileShelfStore()
        self.mirror = MirrorService()
        self.pomodoro = PomodoroService(config: PomodoroConfig(
            workMinutes: settings.settings.pomodoroWorkMinutes,
            shortBreakMinutes: settings.settings.pomodoroShortBreakMinutes,
            longBreakMinutes: settings.settings.pomodoroLongBreakMinutes,
            sessionsBeforeLongBreak: settings.settings.pomodoroSessionsBeforeLongBreak))
        let store = AgentSessionStore()
        self.agentStore = store
        self.approvalPeek = ApprovalPeekCoordinator(
            store: store,
            appState: appState,
            settings: settings
        )
        self.agents = AgentCoordinator(store: store, settings: settings)
        self.permissions = PermissionCoordinator()
        self.pointerTracker = PointerTrackingService()
        self.diagnostics = NotchDiagnostics()
        self.notchLayout = NotchLayoutInfo()
        self.responsive = NotchResponsiveLayoutService()
        let stats = TerminalBridgeStats()
        self.terminalStats = stats
        self.terminalBridge = TerminalAgentBridge(store: store, stats: stats)
        // Verified decision channel: an external responder (Arcus) can accept/deny
        // over an anonymous XPC endpoint. The peer is code-signing verified before
        // any decision reaches the bridge (fail-closed). Skipped under XCTest so
        // unit runs don't start a listener or write the rendezvous file.
        let bridge = self.terminalBridge
        self.agentDecisionService = AgentDecisionService.anonymous { requestID, allow in
            await bridge.respond(requestID: requestID, allow: allow, message: nil)
        }
        if NSClassFromString("XCTestCase") == nil {
            self.agentDecisionService.start()
            AgentDecisionRendezvous.publish(self.agentDecisionService.endpoint)
            // Push presented permission requests to verified external responders.
            let decision = self.agentDecisionService
            Task {
                await bridge.setExternalNotify { req in
                    guard let uuid = UUID(uuidString: req.transactionID) else { return }
                    decision.notify(AgentRequestWire(
                        id: uuid, agent: req.agent, summary: req.summary, detail: req.detail,
                        riskClass: "medium", expiresAtMs: req.expiresAt.timeIntervalSince1970 * 1000))
                }
            }
        }
        self.quickNote = QuickNoteService()
        self.nowPlaying = NowPlayingService(provider: mediaProvider)
        self.battery = BatteryService()
        self.downloads = DownloadsService()
        self.screenshot = ScreenshotService()
        self.liveActivity = LiveActivityCoordinator()
        let community = CommunityModuleRegistry()
        _ = try? community.register(SystemPulseModule.self)
        self.community = community

        self.agentsWorkspace = AgentsWorkspaceController(
            settings: settings, agents: self.agents, store: store, bridge: self.terminalBridge)

        let modules: [NotchModule] = [
            ClipboardModule(),
            FileShelfModule(),
            MirrorModule(),
            PomodoroModule(),
            QuickNoteModule(),
            NowPlayingModule(),
            DownloadsModule(),
            ScreenshotModule(),
            BatteryModule(),
        ]
        let registry = ModuleRegistry(modules: modules, settings: settings)
        self.registry = registry

        // One-time migration: strip Community (e.g. community.system-pulse),
        // workspace and obsolete ids from any saved Home layout so a stale
        // placement can never resurface on Home. Built-in Home order is preserved.
        let eligibleHome = HomeModuleEligibility.definitions(from: registry.allModules)
        if HomeLayoutNormalizer.needsNormalization(settings.settings, definitions: eligibleHome) {
            HomeLayoutNormalizer.normalize(&settings.settings, definitions: eligibleHome)
            settings.saveNow()
        }

        self.dashboard = DashboardModel(settings: settings, registry: registry)

        configure()
    }

    private func configure() {
        clipboard.isPaused = settings.settings.clipboardMonitoringPaused
        clipboard.isPrivateMode = settings.settings.clipboardPrivateMode
        fileShelf.retention = settings.settings.fileShelfRetention
        fileShelf.intakeMode = settings.settings.fileShelfIntakeMode
        fileShelf.retentionPolicy = settings.settings.fileShelfRetentionPolicy
        fileShelf.moveExplained = settings.settings.fileShelfMoveExplained
        if !settings.settings.clipboardMonitoringPaused {
            clipboard.startMonitoring()
        }
        // Agents monitor configuration.
        agentStore.compactDisplay = settings.settings.compactAgentsDisplay
        agentStore.compactAccent = settings.settings.agentCompactAccent
        agentStore.recentLimit = settings.settings.recentSessionLimit
        agentStore.showFailed = settings.settings.showFailedSessions
        agentStore.showExternal = settings.settings.showExternalSessions
        agentStore.completionActivitySeconds = settings.settings.completionActivitySeconds
        Task { [terminalBridge, settings] in
            await terminalBridge.configure(
                mode: settings.settings.agentPermissionHandlingMode,
                fallbackDelay: settings.settings.terminalFallbackDelay.seconds,
                approvalLifetime: settings.settings.approvalAvailability.seconds)
        }

        // Register data-driven live-activity sources. Adding a module with a live
        // activity means registering its source here — no edits to CompactNotchView.
        liveActivity.register(agentStore)
        liveActivity.register(pomodoro)
        liveActivity.register(nowPlaying)
        nowPlaying.start()
    }

    /// Attaches shared services to a view hierarchy as environment objects.
    func inject<Content: View>(_ content: Content) -> some View {
        content
            .environmentObject(self)
            .environmentObject(settings)
            .environmentObject(appState)
            .environmentObject(clipboard)
            .environmentObject(fileShelf)
            .environmentObject(mirror)
            .environmentObject(pomodoro)
            .environmentObject(agentStore)
            .environmentObject(approvalPeek)
            .environmentObject(agents)
            .environmentObject(permissions)
            .environmentObject(registry)
            .environmentObject(community)
            .environmentObject(diagnostics)
            .environmentObject(terminalStats)
            .environmentObject(notchLayout)
            .environmentObject(quickNote)
            .environmentObject(nowPlaying)
            .environmentObject(liveActivity)
            .environmentObject(responsive)
            .environmentObject(dashboard)
            .environmentObject(battery)
            .environmentObject(downloads)
            .environmentObject(screenshot)
    }

    /// Called on quit to honour session-scoped retention and stop the Pomodoro
    /// active state (an explicit quit must not auto-resume the timer next launch;
    /// statistics / session count are preserved).
    func handleQuit() {
        ApplicationShutdownSequence.perform(.init(
            flushSettings: settings.saveNow,
            stopModuleRefreshLoops: { [clipboard, downloads, nowPlaying, mirror] in
                NotificationCenter.default.post(name: .notchDeckWillTerminate, object: nil)
                clipboard.stopMonitoring()
                downloads.stop()
                nowPlaying.stop()
                mirror.stop()
            },
            stopTransientObservers: { [agents, pointerTracker] in
                agents.stopExternalMonitoring()
                agents.stopTerminalPresenceMonitoring()
                pointerTracker.stop()
            },
            endFileShelfSession: fileShelf.handleSessionEnd,
            resetPomodoro: pomodoro.resetActiveStateForQuit,
            requestBridgeShutdown: { [terminalBridge] in
                Task { await terminalBridge.stop() }
            }))
    }
}

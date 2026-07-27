import AppKit
import Combine

/// Orchestrates providers and the session store: launches managed sessions,
/// consumes their event streams, drives status transitions, and exposes
/// availability + external-window controls to the UI.
@MainActor
final class AgentCoordinator: ObservableObject {
    let store: AgentSessionStore
    @Published private(set) var availability: [AgentProviderKind: ProviderAvailability] = [:]
    /// Sessions with an approval decision currently being sent to the bridge.
    @Published private(set) var approvalInFlight: Set<UUID> = []
    /// Non-blocking message shown when a terminal focus request cannot locate the
    /// original tab.
    @Published var lastFocusMessage: String?

    private let terminalController = TerminalController()
    private var terminalPresenceTask: Task<Void, Never>?

    private var providers: [AgentProviderKind: AgentProvider]
    private let externalAdapter: ExternalSessionAdapter
    private let settings: SettingsStore
    private var streamTasks: [UUID: Task<Void, Never>] = [:]

    /// Set by AppEnvironment after construction (avoids an init cycle).
    weak var terminalBridge: TerminalAgentBridge?

    init(store: AgentSessionStore,
         settings: SettingsStore,
         providers: [AgentProviderKind: AgentProvider]? = nil,
         externalAdapter: ExternalSessionAdapter = ExternalSessionAdapter()) {
        self.store = store
        self.settings = settings
        self.externalAdapter = externalAdapter
        if let providers {
            self.providers = providers
        } else {
            let logBytes = settings.settings.agentLogMaxBytes
            let logging = settings.settings.agentLoggingEnabled
            self.providers = [
                .codex: CodexProvider(overridePath: settings.settings.codexPathOverride,
                                      logMaxBytes: logBytes, loggingEnabled: logging),
                .claudeCode: ClaudeProvider(overridePath: settings.settings.claudePathOverride,
                                            logMaxBytes: logBytes, loggingEnabled: logging),
            ]
        }
    }

    func provider(_ kind: AgentProviderKind) -> AgentProvider? { providers[kind] }

    // MARK: Availability

    func refreshAvailability() async {
        for (kind, provider) in providers {
            let result = await provider.detectAvailability()
            availability[kind] = result
        }
    }

    // MARK: Managed sessions

    func startSession(kind: AgentProviderKind, projectURL: URL, prompt: String) async {
        guard let provider = providers[kind] else { return }
        let config = AgentLaunchConfiguration(
            permissionMode: settings.settings.agentPermissionMode,
            model: nil)
        do {
            let (session, stream) = try await provider.startSession(
                projectURL: projectURL, prompt: prompt, configuration: config)
            store.upsert(session)
            consume(stream, sessionID: session.id)
        } catch {
            Log.agents.error("startSession failed: \(error.localizedDescription)")
            var failed = AgentSession(provider: kind, title: prompt, projectPath: projectURL.path,
                                      status: .failed)
            failed.latestSummary = error.localizedDescription
            store.upsert(failed)
        }
    }

    func sendFollowUp(sessionID: UUID, message: String) async {
        guard let session = store.session(id: sessionID),
              let provider = providers[session.provider] else { return }
        store.update(id: sessionID) { $0.status = .running; $0.requiresAttention = false }
        do {
            let stream = try await provider.send(message: message, to: session)
            consume(stream, sessionID: sessionID)
        } catch {
            store.update(id: sessionID) {
                $0.status = .failed
                $0.latestSummary = error.localizedDescription
            }
        }
    }

    func interrupt(sessionID: UUID) async {
        await AgentProcessTable.shared.interrupt(sessionID: sessionID)
        streamTasks[sessionID]?.cancel()
        streamTasks[sessionID] = nil
        store.update(id: sessionID) {
            if $0.status == .running || $0.status == .starting { $0.status = .interrupted }
            $0.requiresAttention = false
        }
    }

    /// Respond to an approval request on a *managed* session by writing to the
    /// process's own stdin (never by simulating keystrokes to a window). Whether
    /// the CLI consumes it depends on the version; we surface a clear fallback in
    /// the UI when a session is external and unintegrated.
    func respond(sessionID: UUID, approve: Bool) async {
        guard let session = store.session(id: sessionID), session.isManaged else { return }
        let line = approve ? "y" : "n"
        await AgentProcessTable.shared.writeLine(line, to: sessionID)
        store.update(id: sessionID) {
            $0.status = approve ? .running : .interrupted
            $0.requiresAttention = false
            $0.latestSummary = approve ? "Approved" : "Denied"
        }
        if !approve { await interrupt(sessionID: sessionID) }
    }

    /// Approve or deny a pending permission request. Routes to the terminal
    /// bridge for hook-connected sessions (decision relayed to the CLI in its own
    /// format) or to managed-process stdin for NotchDeck-launched sessions.
    func decideApproval(session: AgentSession, allow: Bool) async {
        if session.isBridgeConnected, let rid = session.pendingApprovalRequestID {
            await terminalBridge?.respond(requestID: rid, allow: allow, message: allow ? nil : "Denied from NotchDeck")
            store.update(id: session.id) {
                $0.status = allow ? .running : .interrupted
                $0.requiresAttention = false
                $0.pendingApprovalRequestID = nil
                $0.approval?.state = .answered
                $0.approval = nil
                $0.latestSummary = allow ? "Approved" : "Denied"
            }
        } else if session.isManaged {
            await respond(sessionID: session.id, approve: allow)
        }
    }

    /// Focus the EXISTING terminal tab where the agent runs — by TTY, via
    /// Terminal.app focus-only AppleScript (no new window/tab, no `do script`, no
    /// relaunch). On failure it shows a non-blocking message and re-checks the
    /// session's terminal presence immediately; it never activates an unrelated
    /// window or opens a replacement terminal.
    func focusTerminal(_ session: AgentSession) {
        let result = terminalController.lookup(session: session)
        if case .found = result { lastFocusMessage = nil; return }

        // For a non-Terminal (unsupported) window, try precise Accessibility raise.
        if case .unsupportedTerminal = result,
           session.externalBundleID != nil, externalAdapter.focus(session) {
            lastFocusMessage = nil
            return
        }

        // Reason-accurate message; only .missing / terminated read as "gone".
        lastFocusMessage = TerminalFocusFeedback.message(for: result, presence: session.terminalPresence)
        // Re-check lifecycle only when the tab was genuinely not matched.
        if case .ttyNotFound = result { refreshTerminalPresence() }
    }

    // MARK: Terminal presence (lifecycle)

    /// Update every session's terminal presence from a live Terminal.app tab
    /// enumeration, DEBOUNCED: a tab must be confirmed absent three consecutive
    /// enumerations before the session moves to Recent. Query/permission/timeout
    /// errors become `unknown` (session stays Active) and never count as misses.
    /// Active/Recent follows this — NOT hook activity or approvals.
    func refreshTerminalPresence() {
        let result = terminalController.enumerate()
        for session in store.sessions where session.terminalTTY != nil || session.isBridgeConnected {
            let obs = terminalController.observation(for: session, result: result)
            let prev = TerminalPresenceDebounce.State(presence: session.terminalPresence,
                                                      missCount: session.terminalMissCount)
            let next = TerminalPresenceDebounce.step(prev, obs)
            if next != prev {
                store.update(id: session.id) {
                    $0.terminalPresence = next.presence
                    $0.terminalMissCount = next.missCount
                }
            }
        }
    }

    func startTerminalPresenceMonitoring() {
        terminalPresenceTask?.cancel()
        terminalPresenceTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshTerminalPresence()
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
            }
        }
    }

    func stopTerminalPresenceMonitoring() {
        terminalPresenceTask?.cancel()
        terminalPresenceTask = nil
    }

    /// Send an approval decision. Shows "Sending…", delivers the decision to the
    /// live helper on its still-open connection, and only reports "Approved"
    /// (delivered) once the helper acknowledges emitting the CLI JSON. A decision
    /// after fallback/expiry is rejected. "Approved" never means merely clicked.
    func decide(session: AgentSession, allow: Bool) async {
        // Reject a late click: only a live pending approval may be decided.
        guard let current = store.session(id: session.id),
              current.approval?.state == .pending else {
            store.update(id: session.id) {
                if $0.approval?.state == .fellBack {} else { $0.approval?.state = .expired }
            }
            return
        }
        guard current.isBridgeConnected, let rid = current.pendingApprovalRequestID else {
            // Managed (non-bridge) path keeps the simple flow.
            approvalInFlight.insert(session.id)
            await decideApproval(session: session, allow: allow)
            approvalInFlight.remove(session.id)
            return
        }

        approvalInFlight.insert(session.id)
        // DELIVERING: record the decision and disable further interaction, but do
        // NOT show a success state yet. "Approved" is applied ONLY when the helper
        // acknowledges emitting the provider response (bridge → .decisionDelivered).
        store.update(id: session.id) {
            $0.approval?.state = .sending
            $0.approval?.decidedAllow = allow
        }
        AgentApprovalDiagnostics.record(session: session, requestID: rid,
                                        transition: "userDecided\(allow ? "Allow" : "Deny") → delivering")

        let delivered = await terminalBridge?.respond(
            requestID: rid, allow: allow, message: allow ? nil : "Denied in NotchDeck") ?? false
        approvalInFlight.remove(session.id)

        if !delivered {
            // The helper was already gone (timed out / disconnected) → not delivered.
            // Do NOT auto-approve or fake success: show a truthful delivery failure.
            store.update(id: session.id) { $0.approval?.state = .deliveryFailed }
            AgentApprovalDiagnostics.record(session: session, requestID: rid,
                                            transition: "delivering → deliveryFailed (helper gone)")
            return
        }
        // Written to the live helper; still awaiting the emit-ack. If no ack lands
        // shortly, mark deliveryFailed (never a false "Approved").
        let id = session.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            guard let self else { return }
            if self.store.session(id: id)?.approval?.state == .sending {
                self.store.update(id: id) { $0.approval?.state = .deliveryFailed }
                AgentApprovalDiagnostics.record(sessionID: id, requestID: rid,
                                                transition: "delivering → deliveryFailed (no ack)")
            }
        }
    }

    /// Resume a managed session (provider-supported) as a fresh event stream.
    func resume(sessionID: UUID) async {
        guard let session = store.session(id: sessionID),
              let provider = providers[session.provider] else { return }
        store.update(id: sessionID) { $0.status = .running; $0.requiresAttention = false }
        do {
            let stream = try await provider.resume(session)
            consume(stream, sessionID: sessionID)
        } catch {
            store.update(id: sessionID) {
                $0.status = .failed; $0.latestSummary = error.localizedDescription
            }
        }
    }

    private func consume(_ stream: AgentEventStream, sessionID: UUID) {
        streamTasks[sessionID]?.cancel()
        streamTasks[sessionID] = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                if let current = self.store.session(id: sessionID) {
                    let updated = AgentStateReducer.reduce(current, event: event)
                    self.store.upsert(updated)
                }
            }
            await AgentProcessTable.shared.remove(sessionID: sessionID)
            self?.streamTasks[sessionID] = nil
        }
    }

    // MARK: External sessions

    private var externalMonitorTask: Task<Void, Never>?

    var externalControlEnabled: Bool { settings.settings.externalWindowControlEnabled }
    var accessibilityTrusted: Bool { externalAdapter.accessibility.isTrusted }

    func refreshExternalSessions() {
        guard settings.settings.externalWindowControlEnabled else { return }
        let external = externalAdapter.scan()
        store.replaceExternal(external)
    }

    /// Periodically rescan external windows so already-open Codex/Claude sessions
    /// appear without the user doing anything. Cheap; only runs when enabled.
    func startExternalMonitoring() {
        externalMonitorTask?.cancel()
        externalMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshExternalSessions()
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    func stopExternalMonitoring() {
        externalMonitorTask?.cancel()
        externalMonitorTask = nil
    }

    @discardableResult
    func focus(_ session: AgentSession) -> Bool {
        if session.isManaged {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.projectPath)
            return true
        }
        return externalAdapter.focus(session)
    }

    // MARK: Project / terminal helpers

    func openProject(_ session: AgentSession) {
        guard !session.projectPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath))
    }

    func openTerminal(_ session: AgentSession) {
        guard !session.projectPath.isEmpty else { return }
        let url = URL(fileURLWithPath: session.projectPath)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: config)
    }
}

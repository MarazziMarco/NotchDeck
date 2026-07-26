import Foundation
import Darwin

/// Thread-safe holder for the bridge's blocking-I/O state. The accept/read loops
/// run on dedicated background threads (NOT the actor executor), so a blocking
/// `accept()` / `read()` can never stall the actor. State that those threads and
/// the actor both touch lives here behind a lock.
final class BridgeIO: @unchecked Sendable {
    private let lock = NSLock()
    private var _running = false
    var listenFD: Int32 = -1

    var running: Bool { lock.lock(); defer { lock.unlock() }; return _running }
    func setRunning(_ v: Bool) { lock.lock(); _running = v; lock.unlock() }
}

/// Local, user-only bridge that receives real-time events from hook-connected
/// terminal agent sessions over a Unix-domain socket and reflects them into the
/// `AgentSessionStore`. Also answers permission requests with an Allow/Deny
/// decision the helper relays back to the CLI in the provider's own format.
///
/// Threading: blocking socket syscalls run on background threads; all shared
/// mutable state (session map, pending approvals) is actor-isolated; store and
/// stats updates hop to the main actor. Nothing blocks the actor executor.
///
/// Security: socket lives under the user's Application Support in a 0700
/// directory, the socket file is chmod 0600, there is no network port, only
/// sanitized metadata is accepted, and nothing is auto-approved.
actor TerminalAgentBridge {
    private let store: AgentSessionStore
    nonisolated let stats: TerminalBridgeStats
    private nonisolated let io = BridgeIO()
    private var sweepTask: Task<Void, Never>?

    /// providerSessionID → our session UUID.
    private var sessionIDs: [String: UUID] = [:]
    /// requestID → client fd awaiting a decision.
    private var pendingApprovals: [String: Int32] = [:]
    /// session UUID → last event time (for offline sweep).
    private var lastSeen: [UUID: Date] = [:]

    private let heartbeatTimeout: TimeInterval = 45

    /// Permission UX configuration (set from settings via `configure`).
    private var handlingMode: AgentPermissionHandlingMode = .notchWithTerminalFallback
    private var fallbackDelay: TimeInterval = 8

    init(store: AgentSessionStore, stats: TerminalBridgeStats) {
        self.store = store
        self.stats = stats
    }

    func configure(mode: AgentPermissionHandlingMode, fallbackDelay: TimeInterval) {
        self.handlingMode = mode
        self.fallbackDelay = fallbackDelay
    }

    var isListening: Bool { io.running }
    nonisolated var socketPath: String { TerminalAgentProtocol.socketURL().path }

    // MARK: Lifecycle

    func start() {
        guard !io.running else { return }
        let url = TerminalAgentProtocol.socketURL()
        AppPaths.ensureDirectory(url.deletingLastPathComponent())
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: url.deletingLastPathComponent().path)
        unlink(url.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Log.agents.error("bridge: socket() failed"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = url.path
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { cstr in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                        cstr, capacity - 1)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else { Log.agents.error("bridge: bind() failed"); close(fd); return }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { Log.agents.error("bridge: listen() failed"); close(fd); return }

        io.listenFD = fd
        io.setRunning(true)
        Log.agents.info("bridge listening")
        Task { @MainActor [stats] in stats.markListening(true) }

        // Blocking accept loop on a dedicated thread — never on the actor.
        let io = self.io
        let acceptThread = Thread { [weak self] in self?.acceptLoop(fd: fd, io: io) }
        acceptThread.name = "notchdeck.bridge.accept"
        acceptThread.start()

        sweepTask = Task { [weak self] in await self?.sweepLoop() }
    }

    func stop() {
        io.setRunning(false)
        Task { @MainActor [stats] in stats.markListening(false) }
        sweepTask?.cancel()
        if io.listenFD >= 0 { close(io.listenFD); io.listenFD = -1 }
        unlink(TerminalAgentProtocol.socketURL().path)
    }

    // MARK: Blocking I/O (background threads, nonisolated)

    private nonisolated func acceptLoop(fd: Int32, io: BridgeIO) {
        while io.running {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if !io.running { break }
                continue
            }
            Task { @MainActor [stats] in stats.recordConnection() }
            let readThread = Thread { [weak self] in self?.readLoop(client: client, io: io) }
            readThread.name = "notchdeck.bridge.read"
            readThread.start()
        }
    }

    private nonisolated func readLoop(client: Int32, io: BridgeIO) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var pending = Data()
        while io.running {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            pending.append(contentsOf: buffer[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: pending.startIndex..<nl)
                pending.removeSubrange(pending.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) {
                    Task { [weak self] in await self?.handleLine(line, client: client) }
                }
            }
        }
        Task { [weak self] in await self?.dropApprovals(forClient: client) }
    }

    // MARK: Decoding (actor)

    private func handleLine(_ line: String, client: Int32) async {
        guard let event = TerminalAgentCodec.decodeEvent(line) else {
            await MainActor.run { [stats] in stats.recordRejected("non-JSON / undecodable line") }
            return
        }
        guard event.protocolVersion == TerminalAgentProtocol.version else {
            let v = event.protocolVersion
            await MainActor.run { [stats] in stats.recordRejected("protocol version \(v) != \(TerminalAgentProtocol.version)") }
            return
        }
        await ingest(event, client: client)
    }

    private func dropApprovals(forClient client: Int32) {
        for (rid, f) in pendingApprovals where f == client { pendingApprovals[rid] = nil }
        close(client)
    }

    private func ingest(_ event: TerminalAgentEvent, client: Int32) async {
        let uuid = sessionIDs[event.sessionID] ?? {
            let id = UUID(); sessionIDs[event.sessionID] = id; return id
        }()
        lastSeen[uuid] = Date()

        if event.type == .permissionRequested, let rid = event.requestID {
            pendingApprovals[rid] = client
        }

        // Helper acknowledged emitting the CLI decision → mark the approval as
        // truly delivered so the card can show "Approved".
        if event.type == .decisionDelivered {
            await MainActor.run { [store] in
                store.update(id: uuid) {
                    if $0.approval?.state == .sending || $0.approval?.state == .pending {
                        $0.approval?.state = .delivered
                    }
                }
            }
            return
        }

        let mode = handlingMode
        let delay = fallbackDelay
        await MainActor.run { [store, stats] in
            let existing = store.session(id: uuid)
            let updated = Self.reduce(existing: existing, id: uuid, event: event,
                                      handlingMode: mode, fallbackDelay: delay)
            // SessionStart (and every event) updates the store immediately on the
            // MainActor — no waiting on the 5s external scan.
            store.upsert(updated)
            stats.recordDecoded(type: event.type.rawValue, connectedTitle: updated.title)
            let all = store.sessions
            stats.syncStoreCounts(total: all.count,
                                  connected: all.filter { $0.connectivity == .connected }.count,
                                  external: all.filter { $0.connectivity == .external }.count)
        }
    }

    /// Pure reduction of a bridge event onto a session — unit-testable. Strictly
    /// distinguishes activity from approval: ONLY a genuine PermissionRequest
    /// (`.permissionRequested`) creates a `PendingApproval`. PreToolUse
    /// (`.toolStarted`) is activity only and never yields Allow/Deny.
    static func reduce(existing: AgentSession?, id: UUID, event: TerminalAgentEvent,
                       handlingMode: AgentPermissionHandlingMode = .notchWithTerminalFallback,
                       fallbackDelay: TimeInterval = 8,
                       now: Date = Date()) -> AgentSession {
        var s = existing ?? AgentSession(
            id: id,
            provider: event.provider == .claudeCode ? .claudeCode : .codex,
            providerSessionID: event.sessionID,
            title: event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Terminal session",
            projectPath: event.cwd ?? "",
            status: .running,
            isManaged: false)
        s.isBridgeConnected = true
        s.lastActivityAt = Date(timeIntervalSince1970: event.timestamp)
        s.terminalTTY = event.tty ?? s.terminalTTY
        s.terminalAppName = event.terminalApp ?? s.terminalAppName
        s.pid = event.pid ?? s.pid
        s.ppid = event.ppid ?? s.ppid
        s.shellPID = event.shellPID ?? s.shellPID
        s.termSessionID = event.termSessionID ?? s.termSessionID
        // Resolve the terminal bundle id (explicit, or inferred from Apple Terminal).
        if let bid = event.terminalBundleID { s.terminalBundleID = bid }
        else if let app = event.terminalApp?.lowercased(),
                app.contains("terminal"), !app.contains("iterm") {
            s.terminalBundleID = TerminalController.terminalBundleID
        }
        if let cwd = event.cwd { s.projectPath = cwd }

        // A resolving event clears any live approval (tool executed / turn ended).
        if ApprovalClassifier.clearsApproval(event.type) {
            s.approval = nil
            s.pendingApprovalRequestID = nil
            s.requiresAttention = false
        }

        switch event.type {
        case .sessionStarted, .sessionResumed:
            s.status = .running; s.requiresAttention = false
        case .userPromptSubmitted:
            s.status = .running
        case .toolStarted:
            // PreToolUse — activity ONLY. Never approval.
            s.status = .running
            let summary = AgentLatestMessage.sanitize(event.summary ?? event.toolName.map { "Using \($0)" } ?? "")
            if !summary.isEmpty { s.latestSummary = summary }
        case .permissionRequested:
            // Idempotent: a duplicate PermissionRequest for the same live request
            // must not create a second approval.
            if let existingApproval = s.approval, existingApproval.isLive,
               existingApproval.requestID == (event.requestID ?? "") {
                return s
            }
            let summary = AgentLatestMessage.sanitize(event.summary ?? "Permission requested")
            let fallbackDeadline = handlingMode == .notchWithTerminalFallback
                ? now.addingTimeInterval(fallbackDelay) : nil
            s.status = .waitingForApproval
            s.requiresAttention = handlingMode.showsFunctionalDecision
            s.pendingApprovalRequestID = event.requestID
            s.latestSummary = summary
            s.approval = PendingApproval(
                provider: s.provider,
                sessionID: event.sessionID,
                requestID: event.requestID ?? "",
                toolUseID: event.toolUseID,
                turnID: event.turnID,
                rawEventName: "PermissionRequest",
                toolName: event.toolName,
                summary: summary,
                receivedAt: now,
                expiresAt: now.addingTimeInterval(120),
                state: .pending,
                handlingMode: handlingMode,
                fallbackDeadline: fallbackDeadline,
                nativePromptExpected: handlingMode.nativePromptExpected)
        case .toolCompleted:
            s.status = .running               // approval already cleared above
        case .agentStopped:
            s.status = .completed; s.requiresAttention = false
            if let msg = event.lastAssistantMessage {
                let m = AgentLatestMessage.sanitize(msg)
                if !m.isEmpty { s.latestSummary = m }
            }
        case .sessionEnded:
            s.status = .completed; s.requiresAttention = false; s.isBridgeConnected = false
        case .heartbeat, .decisionDelivered:
            break
        }
        return s
    }

    // MARK: Approvals

    @discardableResult
    func respond(requestID: String, allow: Bool, message: String?) -> Bool {
        guard let fd = pendingApprovals[requestID] else { return false }
        let decision = TerminalAgentDecision(requestID: requestID,
                                             behavior: allow ? .allow : .deny, message: message)
        if let data = TerminalAgentCodec.encodeLine(decision) {
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        }
        pendingApprovals[requestID] = nil
        return true
    }

    /// Release a still-blocked helper at the hybrid fallback deadline: tell it to
    /// stop waiting and return empty stdout (native prompt).
    @discardableResult
    func releaseForFallback(requestID: String) -> Bool {
        guard let fd = pendingApprovals[requestID] else { return false }
        let release = TerminalAgentDecision(requestID: requestID, behavior: .deny, fallback: true)
        if let data = TerminalAgentCodec.encodeLine(release) {
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        }
        pendingApprovals[requestID] = nil
        return true
    }

    // MARK: Offline sweep

    private func sweepLoop() async {
        while io.running {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            let now = Date()
            // Approval fallback / expiry sweep (runs frequently for a live countdown).
            let releaseRequestIDs: [String] = await MainActor.run { [store] in
                var releases: [String] = []
                for session in store.sessions {
                    guard let approval = session.approval, approval.isLive else { continue }
                    if approval.isExpired(now: now) {
                        // Fail safe — never auto-approve. Clear and resume running.
                        store.update(id: session.id) {
                            $0.approval?.state = .expired; $0.approval = nil
                            $0.pendingApprovalRequestID = nil
                            $0.requiresAttention = false
                            if $0.status == .waitingForApproval { $0.status = .running }
                        }
                    } else if let deadline = approval.fallbackDeadline, now >= deadline {
                        let rid = approval.requestID
                        store.update(id: session.id) {
                            $0.approval?.state = .fellBack
                            $0.requiresAttention = false
                        }
                        releases.append(rid)
                    }
                }
                return releases
            }
            for rid in releaseRequestIDs { releaseForFallback(requestID: rid) }
            // Heartbeat sweep: a quiet session is NOT gone. Mark it idle but keep
            // it connected and Active — only terminal presence (the tab closing)
            // moves it to Recent.
            let stale = lastSeen.filter { now.timeIntervalSince($0.value) > heartbeatTimeout }
            for (uuid, _) in stale {
                lastSeen[uuid] = nil
                await MainActor.run { [store] in
                    store.update(id: uuid) {
                        if $0.isBridgeConnected && [.running, .starting].contains($0.status) {
                            $0.status = .idle
                        }
                    }
                }
            }
        }
    }
}

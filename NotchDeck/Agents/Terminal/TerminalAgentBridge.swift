import Foundation
import Darwin

enum BridgeLifecycleError: Error, LocalizedError {
    case pathTooLong(String, Int)
    case alreadyRunning(String)
    case systemCall(operation: String, path: String, code: Int32)
    case fileSystem(operation: String, path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .pathTooLong(let path, let bytes):
            return "Bridge socket path is \(bytes) UTF-8 bytes; Darwin requires fewer than 104: \(path)"
        case .alreadyRunning(let path):
            return "Another NotchDeck bridge is already listening at \(path)."
        case .systemCall(let operation, let path, let code):
            return "Bridge \(operation) failed at \(path): [errno \(code)] \(String(cString: strerror(code)))."
        case .fileSystem(let operation, let path, let detail):
            return "Bridge \(operation) failed at \(path): \(detail)."
        }
    }
}

/// An owned Unix listener. Cleanup verifies that the filesystem path still
/// points at this listener's inode while holding the launch lock, so an instance
/// that never acquired the socket cannot remove another instance's endpoint.
final class BridgeSocketLease: @unchecked Sendable {
    private let stateLock = NSLock()
    private var descriptor: Int32
    private let device: dev_t
    private let inode: ino_t
    let path: String
    let lockPath: String

    init(descriptor: Int32, path: String, lockPath: String, device: dev_t, inode: ino_t) {
        self.descriptor = descriptor
        self.path = path
        self.lockPath = lockPath
        self.device = device
        self.inode = inode
    }

    var fileDescriptor: Int32 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return descriptor
    }

    func closeAndUnlink() {
        stateLock.lock()
        guard descriptor >= 0 else {
            stateLock.unlock()
            return
        }
        let fd = descriptor
        descriptor = -1
        stateLock.unlock()

        let launchLock = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if launchLock >= 0 { _ = flock(launchLock, LOCK_EX) }
        defer {
            if launchLock >= 0 {
                _ = flock(launchLock, LOCK_UN)
                close(launchLock)
            }
        }

        var current = stat()
        let sameEndpoint = lstat(path, &current) == 0
            && current.st_dev == device
            && current.st_ino == inode
        close(fd)
        if sameEndpoint { _ = unlink(path) }
    }

    deinit { closeAndUnlink() }
}

enum BridgeSocketBootstrap {
    static let darwinPathCapacity = 104
    static let defaultProbeTimeoutMilliseconds: Int32 = 200

    static func bind(path: String, backlog: Int32 = 16,
                     probeTimeoutMilliseconds: Int32 = defaultProbeTimeoutMilliseconds) throws
        -> BridgeSocketLease {
        let byteCount = path.utf8.count
        guard byteCount < darwinPathCapacity else {
            throw BridgeLifecycleError.pathTooLong(path, byteCount)
        }

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw BridgeLifecycleError.fileSystem(
                operation: "prepare directory",
                path: directory.path,
                detail: error.localizedDescription
            )
        }

        let lockPath = directory.appendingPathComponent("terminal-bridge.lock").path
        let lockFD = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else {
            throw systemError("open lockfile", lockPath)
        }
        defer {
            _ = flock(lockFD, LOCK_UN)
            close(lockFD)
        }
        guard flock(lockFD, LOCK_EX) == 0 else {
            throw systemError("lock", lockPath)
        }

        var existing = stat()
        if lstat(path, &existing) == 0 {
            if existing.st_mode & S_IFMT == S_IFSOCK {
                if try probe(path: path, timeoutMilliseconds: probeTimeoutMilliseconds) {
                    throw BridgeLifecycleError.alreadyRunning(path)
                }
            }
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                throw BridgeLifecycleError.fileSystem(
                    operation: "remove stale socket",
                    path: path,
                    detail: error.localizedDescription
                )
            }
        } else if errno != ENOENT {
            throw systemError("inspect", path)
        }

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw systemError("socket", path) }
        var keepListener = false
        defer { if !keepListener { close(listener) } }

        var noSignal: Int32 = 1
        _ = setsockopt(listener, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                       socklen_t(MemoryLayout<Int32>.size))
        var address = try socketAddress(path: path)
        let bound = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw systemError("bind", path) }
        guard chmod(path, 0o600) == 0 else {
            let code = errno
            _ = unlink(path)
            throw BridgeLifecycleError.systemCall(operation: "chmod", path: path, code: code)
        }
        guard listen(listener, backlog) == 0 else {
            let code = errno
            _ = unlink(path)
            throw BridgeLifecycleError.systemCall(operation: "listen", path: path, code: code)
        }

        var info = stat()
        guard lstat(path, &info) == 0 else {
            let code = errno
            _ = unlink(path)
            throw BridgeLifecycleError.systemCall(
                operation: "inspect bound socket", path: path, code: code
            )
        }
        keepListener = true
        return BridgeSocketLease(
            descriptor: listener,
            path: path,
            lockPath: lockPath,
            device: info.st_dev,
            inode: info.st_ino
        )
    }

    /// Returns true only for a live listener. A refused or vanished socket is
    /// stale; every other error is surfaced and therefore never authorizes unlink.
    private static func probe(path: String, timeoutMilliseconds: Int32) throws -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError("probe socket", path) }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw systemError("configure probe", path)
        }
        var address = try socketAddress(path: path)
        let result = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 { return true }
        let initialError = errno
        if initialError == ECONNREFUSED || initialError == ENOENT { return false }
        guard initialError == EINPROGRESS || initialError == EAGAIN else {
            throw BridgeLifecycleError.systemCall(
                operation: "probe connect", path: path, code: initialError
            )
        }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&descriptor, 1, timeoutMilliseconds)
        guard pollResult > 0 else {
            let code = pollResult == 0 ? ETIMEDOUT : errno
            throw BridgeLifecycleError.systemCall(
                operation: "probe connect", path: path, code: code
            )
        }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            throw systemError("read probe result", path)
        }
        if socketError == 0 { return true }
        if socketError == ECONNREFUSED || socketError == ENOENT { return false }
        throw BridgeLifecycleError.systemCall(
            operation: "probe connect", path: path, code: socketError
        )
    }

    private static func socketAddress(path: String) throws -> sockaddr_un {
        let byteCount = path.utf8.count
        guard byteCount < darwinPathCapacity else {
            throw BridgeLifecycleError.pathTooLong(path, byteCount)
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString {
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    $0,
                    capacity - 1
                )
            }
        }
        return address
    }

    private static func systemError(_ operation: String, _ path: String) -> BridgeLifecycleError {
        BridgeLifecycleError.systemCall(operation: operation, path: path, code: errno)
    }
}

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

private struct PendingApprovalConnection {
    let clientFD: Int32
    let providerRequestID: String
    let appSessionID: UUID
    let actionableUntil: Date
}

/// A permission request surfaced to an external verified responder (Arcus).
struct ExternalPendingRequest: Sendable {
    let transactionID: String
    let agent: String
    let summary: String
    let detail: String
    let expiresAt: Date
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
    private nonisolated let socketURL: URL
    private nonisolated let io = BridgeIO()
    private var socketLease: BridgeSocketLease?
    private var sweepTask: Task<Void, Never>?

    /// provider + providerSessionID → our session UUID.
    private var sessionIDs: [String: UUID] = [:]
    /// Per-helper transaction UUID → exact live socket and correlated identities.
    /// Provider-native request IDs are not globally unique and never key this map.
    private var pendingApprovals: [String: PendingApprovalConnection] = [:]
    /// session UUID → last event time (for offline sweep).
    private var lastSeen: [UUID: Date] = [:]

    private let heartbeatTimeout: TimeInterval = 45

    /// Optional sink: pushes a presented permission request to an external verified
    /// responder (the Arcus decision channel). Additive; nil = no external peer.
    private var externalNotify: (@Sendable (ExternalPendingRequest) -> Void)?
    func setExternalNotify(_ cb: @escaping @Sendable (ExternalPendingRequest) -> Void) {
        externalNotify = cb
    }

    /// Permission UX configuration (set from settings via `configure`).
    private var handlingMode: AgentPermissionHandlingMode = .notchWithTerminalFallback
    private var fallbackDelay: TimeInterval = 8
    /// User-configured mirrored-approval lifetime (seconds), clamped to the
    /// internal transport ceiling. New transactions use the current value; a
    /// pending transaction keeps the deadline it was created with.
    private var approvalLifetime: TimeInterval = ApprovalAvailability.default.seconds

    /// Whether the Agents UI module is available to present approvals. When the
    /// Agents module is DISABLED the socket stays alive (a minimal responder) so
    /// synchronous hooks never hang, but every incoming permission request is
    /// released IMMEDIATELY to the provider's native terminal prompt. Nothing is
    /// swallowed, auto-approved or indefinitely delayed.
    private var uiAvailable: Bool = true
    func setUIAvailable(_ available: Bool) async {
        uiAvailable = available
        if !available {
            await releaseAllPendingToTerminal(reason: "fallback:ui-disabled")
        }
    }

    init(store: AgentSessionStore, stats: TerminalBridgeStats,
         socketURL: URL = TerminalAgentProtocol.socketURL()) {
        self.store = store
        self.stats = stats
        self.socketURL = socketURL
    }

    func configure(mode: AgentPermissionHandlingMode, fallbackDelay: TimeInterval,
                   approvalLifetime: TimeInterval = ApprovalAvailability.default.seconds) async {
        self.handlingMode = mode
        self.fallbackDelay = min(fallbackDelay, HookTimeouts.maximumUIFallbackSeconds)
        self.approvalLifetime = min(max(approvalLifetime, 1), HookTimeouts.maxApprovalLifetimeSeconds)
        if mode == .terminalOnly {
            await releaseAllPendingToTerminal(reason: "fallback:terminal-only")
        }
    }

    var isListening: Bool { io.running }
    nonisolated var socketPath: String { socketURL.path }

    // MARK: Lifecycle

    func start() {
        guard !io.running else { return }
        let url = socketURL
        let lease: BridgeSocketLease
        do {
            lease = try BridgeSocketBootstrap.bind(path: url.path)
        } catch {
            Log.agents.error("bridge lifecycle failed: \(error.localizedDescription)")
            Task { @MainActor [stats] in stats.recordLifecycleFailure(error.localizedDescription) }
            return
        }
        let fd = lease.fileDescriptor
        socketLease = lease

        io.listenFD = fd
        io.setRunning(true)
        Log.agents.info("bridge listening")
        Task { @MainActor [stats] in
            stats.recordLifecycleFailure(nil)
            stats.markListening(true)
        }

        // Blocking accept loop on a dedicated thread — never on the actor.
        let io = self.io
        let acceptThread = Thread { [weak self] in self?.acceptLoop(fd: fd, io: io) }
        acceptThread.name = "notchdeck.bridge.accept"
        acceptThread.start()

        sweepTask = Task { [weak self] in await self?.sweepLoop() }
    }

    func stop() async {
        await releaseAllPendingToTerminal(reason: "fallback:bridge-stopping")
        io.setRunning(false)
        Task { @MainActor [stats] in stats.markListening(false) }
        sweepTask?.cancel()
        socketLease?.closeAndUnlink()
        socketLease = nil
        io.listenFD = -1
    }

    // MARK: Blocking I/O (background threads, nonisolated)

    private nonisolated func acceptLoop(fd: Int32, io: BridgeIO) {
        while io.running {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if !io.running { break }
                continue
            }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                       socklen_t(MemoryLayout<Int32>.size))
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
                    // Preserve JSONL ordering per helper connection. In
                    // particular, `responseWritten` must be reduced before
                    // `helperExited`; independent Tasks can otherwise enqueue
                    // onto the actor out of order. This blocks only the
                    // dedicated client thread, never the actor or main thread.
                    let handled = DispatchSemaphore(value: 0)
                    Task { [weak self] in
                        await self?.handleLine(line, client: client)
                        handled.signal()
                    }
                    handled.wait()
                }
            }
        }
        Task { [weak self] in await self?.dropApprovals(forClient: client) }
    }

    // MARK: Decoding (actor)

    private func handleLine(_ line: String, client: Int32) async {
        guard let event = TerminalAgentCodec.decodeEvent(line) else {
            AgentApprovalDiagnostics.recordHookDecodeFailure()
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
        let disconnected = pendingApprovals.compactMap {
            $0.value.clientFD == client ? ($0.key, $0.value) : nil
        }
        for (transactionID, connection) in disconnected {
            pendingApprovals[transactionID] = nil
            Task { @MainActor [store] in
                store.update(id: connection.appSessionID) {
                    // Socket EOF = the ACTUAL, externally-observed helper
                    // termination (distinct from the self-emitted hint).
                    Self.applyHelperTermination(&$0, requestID: transactionID)
                }
            }
        }
        close(client)
    }

    private func ingest(_ event: TerminalAgentEvent, client: Int32) async {
        let providerKind: AgentProviderKind
        switch event.provider {
        case .claudeCode: providerKind = .claudeCode
        case .codex: providerKind = .codex
        case .unknown:
            await MainActor.run { [stats] in
                stats.recordRejected("unsupported permission provider")
            }
            return
        }
        await MainActor.run { [stats] in
            stats.recordObservedProvider(event.provider)
        }
        let currentSessions = await MainActor.run { [store] in store.sessions }
        let ancestry = event.pid.map { MacProcessAncestry.identities(from: $0) } ?? []
        let correlation = AgentHookProcessCorrelator.match(
            provider: providerKind,
            ancestorIdentities: ancestry,
            cwd: event.cwd,
            discoveredAt: Date(timeIntervalSince1970: event.timestamp),
            sessions: currentSessions
        )
        AgentApprovalDiagnostics.recordHook(
            event: event,
            decoded: true,
            correlation: correlation?.confidence
        )
        let sessionKey = "\(event.provider.rawValue):\(event.sessionID)"
        let uuid = correlation?.sessionID ?? sessionIDs[sessionKey] ?? UUID()
        sessionIDs[sessionKey] = uuid
        lastSeen[uuid] = Date()

        // PermissionRequest is the provider-specific synchronous decision
        // channel. The exact helper connection owns the request.
        if event.type == .permissionRequested {
            guard let providerRequestID = event.requestID,
                  let transactionID = event.transactionID,
                  !providerRequestID.isEmpty,
                  !transactionID.isEmpty else {
                await MainActor.run { [stats] in
                    stats.recordRejected("PermissionRequest missing transaction identity")
                }
                return
            }
            if let existing = pendingApprovals[transactionID] {
                guard existing.clientFD == client else {
                    await MainActor.run { [stats] in
                        stats.recordRejected("duplicate transaction identity")
                    }
                    return
                }
            }
            pendingApprovals[transactionID] = PendingApprovalConnection(
                clientFD: client,
                providerRequestID: providerRequestID,
                appSessionID: uuid,
                actionableUntil: Date().addingTimeInterval(approvalLifetime)
            )
            // Agents UI disabled: do not wait for an approval UI that will never
            // appear. Release the helper at once so the provider resumes its native
            // permission flow (safe fallback, never auto-approve).
            if !uiAvailable || handlingMode == .terminalOnly {
                let reason = uiAvailable ? "fallback:terminal-only" : "fallback:ui-disabled"
                await MainActor.run { [stats] in stats.recordDecoded(type: reason, connectedTitle: "") }
                releaseForFallback(requestID: transactionID)
                return
            }
            // Presented in the notch UI → also push to any verified external
            // responder (Arcus). Fire-and-forget; the decision still returns over
            // the verified channel and is applied by `respond`.
            if let externalNotify {
                let summaryText = AgentLatestMessage.sanitize(event.summary
                    ?? event.toolName.map { "\($0) — permission requested" } ?? "Permission requested")
                externalNotify(ExternalPendingRequest(
                    transactionID: transactionID,
                    agent: providerKind == .claudeCode ? "Claude Code" : "Codex",
                    summary: summaryText,
                    detail: event.toolName ?? summaryText,
                    expiresAt: Date().addingTimeInterval(approvalLifetime)))
            }
        }

        // A stale v3 PreToolUse helper may still block. Never surface or answer it
        // with the PermissionRequest encoder: release it to the native flow.
        if event.type == .toolPermissionRequested,
           let providerRequestID = event.requestID {
            let transactionID = event.transactionID ?? UUID().uuidString
            pendingApprovals[transactionID] = PendingApprovalConnection(
                clientFD: client,
                providerRequestID: providerRequestID,
                appSessionID: uuid,
                actionableUntil: .distantPast
            )
            releaseForFallback(requestID: transactionID)
            return
        }

        // Helper wrote+flushed the provider response. This proves ONLY that the
        // bytes were emitted — the UI moves to "Sent to Claude" (`.sent`), never
        // "Approved". Real acceptance is inferred later from provider progression.
        if event.type == .responseWritten || event.type == .decisionDelivered {
            await MainActor.run { [store] in
                store.update(id: uuid) {
                    Self.applyResponseWritten(&$0, requestID: event.transactionID)
                }
            }
            return
        }
        // Self-emitted "I closed stdout and am about to exit" hint. NOT proof of
        // real termination (that is the socket-EOF path in `dropApprovals`).
        if event.type == .providerOutputClosed || event.type == .helperExited {
            await MainActor.run { [store] in
                store.update(id: uuid) {
                    Self.applyProviderOutputClosed(&$0, requestID: event.transactionID)
                }
            }
            return
        }

        if event.type == .agentStopped || event.type == .sessionEnded {
            await releasePendingToTerminal(
                for: uuid,
                reason: "fallback:provider-session-ended"
            )
        }

        let mode = handlingMode
        let delay = fallbackDelay
        let lifetime = approvalLifetime
        await MainActor.run { [store, stats] in
            let existing = store.session(id: uuid)
            let updated = Self.reduce(existing: existing, id: uuid, event: event,
                                      handlingMode: mode, fallbackDelay: delay,
                                      approvalLifetime: lifetime)
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
                       approvalLifetime: TimeInterval = ApprovalAvailability.default.seconds,
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
        s.providerSessionID = event.sessionID
        s.lastActivityAt = Date(timeIntervalSince1970: event.timestamp)
        // Canonicalise on store ("ttys003" → "/dev/ttys003"); a later event with no
        // TTY must NEVER overwrite a valid stored one with nil.
        if let t = event.tty, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            s.terminalTTY = TerminalFocus.normalizeTTY(t)
        }
        s.terminalAppName = event.terminalApp ?? s.terminalAppName
        // event.pid/ppid identify the hook helper. They are diagnostic ancestry
        // inputs only and must never replace the agent process identity.
        s.shellPID = event.shellPID ?? s.shellPID
        s.termSessionID = event.termSessionID ?? s.termSessionID
        // Resolve the terminal bundle id (explicit, or inferred from Apple Terminal).
        if let bid = event.terminalBundleID { s.terminalBundleID = bid }
        else if let app = event.terminalApp?.lowercased(),
                app.contains("terminal"), !app.contains("iterm") {
            s.terminalBundleID = TerminalController.terminalBundleID
        }
        if let cwd = event.cwd { s.projectPath = cwd }

        // Provider progression: a PostToolUse (`toolCompleted`) for the tool whose
        // decision we sent proves the CLI ACCEPTED it and continued — the only
        // truthful basis for "Claude continued". Record it before the approval is
        // cleared below. Correlated by tool-use id (never by timestamp/name).
        let matchingProgress = event.type == .toolCompleted
            && s.approval.map { Self.providerProgressMatches($0, event: event) } == true
        let matchingQueuedRequestID = event.type == .toolCompleted
            ? (s.queuedApprovals ?? []).first {
                Self.providerProgressMatches($0, event: event)
            }?.requestID
            : nil
        // Claude's PermissionRequest payload does not reliably expose the later
        // PostToolUse `tool_use_id`. When exactly one request exists, a same-tool
        // PostToolUse in the same provider session is nevertheless authoritative
        // proof that this request was resolved (including a direct Terminal
        // response). Never apply this fallback while another request is queued.
        let resolvesSingleMatchingTool = event.type == .toolCompleted
            && (s.queuedApprovals?.isEmpty ?? true)
            && s.approval.map { Self.toolNameMatches($0, event: event) } == true
        // After an explicit native fallback, a session-correlated PostToolUse
        // may lack the PermissionRequest's tool identity (notably in Claude).
        // It may clear one unambiguous fallback card, but never claims that a
        // NotchDeck decision was accepted and never touches a queued request.
        let resolvesUnambiguousFallback = event.type == .toolCompleted
            && s.approval?.state == .fellBack
            && (s.queuedApprovals?.isEmpty ?? true)
        if matchingProgress, let ap = s.approval,
           ap.state == .sent || ap.state == .sending
            || ap.state == .providerOutputClosed || ap.state == .helperTerminated
            || ap.state == .helperExited,
           Self.providerProgressMatches(ap, event: event) {
            // Provider progression (PostToolUse) with matching identity is the ONLY
            // truthful basis for "continued" — mark `.delivered` before the
            // resolving event clears the approval.
            s.approval?.state = .delivered
            let name = s.provider.displayName
            s.latestSummary = (ap.decidedAllow ?? true) ? "\(name) continued" : "Tool denied"
        }

        // Stop/SessionEnd are session-wide. PostToolUse only resolves the exact
        // provider-native transaction; unrelated concurrent requests survive.
        if event.type == .agentStopped || event.type == .sessionEnded {
            s.approval = nil
            s.queuedApprovals = nil
            s.pendingApprovalRequestID = nil
            s.requiresAttention = false
        } else if matchingProgress || resolvesSingleMatchingTool
                    || resolvesUnambiguousFallback {
            Self.finishCurrentTransaction(&s)
        } else if let matchingQueuedRequestID {
            var queued = s.queuedApprovals ?? []
            queued.removeAll { $0.requestID == matchingQueuedRequestID }
            s.queuedApprovals = queued.isEmpty ? nil : queued
        }

        switch event.type {
        case .sessionStarted, .sessionResumed:
            s.status = .running; s.requiresAttention = false
        case .userPromptSubmitted:
            s.status = .running
        case .toolStarted:
            // Legacy PreToolUse-as-activity (older helpers). Activity ONLY.
            s.status = .running
            let summary = AgentLatestMessage.sanitize(event.summary ?? event.toolName.map { "Using \($0)" } ?? "")
            if !summary.isEmpty { s.latestSummary = summary }
        case .toolPermissionRequested:
            // Legacy v3 event. It is released by ingest and never creates an
            // approval with a mismatched provider response schema.
            s.status = .running
        case .permissionRequested:
            if handlingMode == .terminalOnly {
                s.status = .running
                s.requiresAttention = false
                s.pendingApprovalRequestID = nil
                s.latestSummary = "Respond in Terminal"
                return s
            }
            // Idempotent: a duplicate for the same provider request identity must
            // not create a second approval.
            let requestID = event.transactionID ?? event.requestID ?? ""
            if s.approval?.requestID == requestID
                || (s.queuedApprovals ?? []).contains(where: { $0.requestID == requestID }) {
                return s
            }
            // Retire only transactions whose provider/helper lifecycle already
            // ended. Local expiry/fallback/delivery failure remains the same
            // terminal-pending transaction and must not be displaced merely
            // because another concurrent request arrives.
            if let current = s.approval {
                switch current.state {
                case .sent, .providerOutputClosed, .helperTerminated,
                     .helperExited, .delivered, .answered, .cancelled:
                    Self.finishCurrentTransaction(&s)
                case .pending, .sending, .deliveryFailed, .fellBack, .expired:
                    break
                }
            }
            let summary = AgentLatestMessage.sanitize(event.summary
                ?? event.toolName.map { "\($0) — permission requested" } ?? "Permission requested")
            // The card stays actionable for the configured approval lifetime.
            // Terminal remains answerable the whole time (mirrored) — this is NOT
            // a "delay before the terminal prompt". At the end the still-blocked
            // helper is released so it cannot hang; it never auto-allows/denies.
            // The lifetime is clamped to the internal transport ceiling so a
            // 5-minute selection is genuinely supported end-to-end.
            let lifetime = min(max(approvalLifetime, 1), HookTimeouts.maxApprovalLifetimeSeconds)
            // In modes where the native terminal prompt is expected (mirrored /
            // fallback), releasing the helper when the lifetime elapses returns the
            // request to the already-visible terminal prompt.
            let fallbackDeadline = handlingMode.nativePromptExpected
                ? now.addingTimeInterval(lifetime) : nil
            s.status = .waitingForApproval
            s.requiresAttention = handlingMode.showsFunctionalDecision
            s.latestSummary = summary
            let transaction = PendingApproval(
                provider: s.provider,
                sessionID: event.sessionID,
                requestID: requestID,
                providerRequestID: event.requestID,
                toolUseID: event.toolUseID,
                turnID: event.turnID,
                rawEventName: "PermissionRequest",
                toolName: event.toolName,
                summary: summary,
                receivedAt: now,
                // The transaction stops being actionable at exactly its assigned
                // deadline. Transport hard deadlines remain safely beyond it.
                expiresAt: now.addingTimeInterval(lifetime),
                state: .pending,
                handlingMode: handlingMode,
                fallbackDeadline: fallbackDeadline,
                nativePromptExpected: handlingMode.nativePromptExpected)
            if s.approval == nil {
                s.approval = transaction
                s.pendingApprovalRequestID = requestID
            } else {
                var queued = s.queuedApprovals ?? []
                queued.append(transaction)
                s.queuedApprovals = queued
            }
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
        case .heartbeat, .responseWritten, .providerOutputClosed, .helperExited, .decisionDelivered:
            break
        }
        return s
    }

    /// Apply a `responseWritten` acknowledgement (pure + unit-testable). This
    /// proves ONLY that the helper wrote+flushed the provider response — NOT that
    /// the provider accepted it. So the request moves to `.sent` ("Sent to
    /// Claude"); it is NEVER shown as "Approved" here. The approval surface stays
    /// briefly as a non-interactive "Sent…" state and is finalised to "Claude
    /// continued" only when provider progression (PostToolUse) is observed, or
    /// cleared by a resolving event. A late/duplicate ack is a no-op.
    static func applyResponseWritten(_ s: inout AgentSession, requestID: String? = nil) {
        guard let approval = s.approval,
              requestID == nil || approval.requestID == requestID,
              approval.state == .sending || approval.state == .pending else { return }
        let allow = approval.decidedAllow ?? true
        s.approval?.state = .sent
        s.requiresAttention = false
        let name = s.provider.displayName
        s.latestSummary = allow ? "Sent to \(name)" : "Denial sent to \(name)"
        // Keep the approval object (non-interactive) so the card can show "Sent…";
        // a subsequent PostToolUse finalises it, or a resolving event clears it.
    }

    /// The helper self-reported that it wrote+closed stdout and is about to exit.
    /// Truthfully this is "provider output closed" — NOT proof the process has
    /// terminated (see `applyHelperTermination`, driven by socket EOF) and NOT
    /// proof the provider accepted the response.
    static func applyProviderOutputClosed(_ s: inout AgentSession, requestID: String? = nil) {
        guard let approval = s.approval,
              requestID == nil || approval.requestID == requestID,
              approval.state == .sent || approval.state == .sending else { return }
        s.approval?.state = .providerOutputClosed
        if s.queuedApprovalCount > 0 {
            Self.finishCurrentTransaction(&s)
        }
    }

    /// Actual helper termination, observed EXTERNALLY by the bridge as socket EOF
    /// (the helper's `close(fd)`/exit). If the transaction was already answered
    /// (decision written), this is a clean end → `.helperTerminated` (provider
    /// acceptance still pending, confirmed later by progression). If it was still
    /// unanswered, the helper died without our decision → release to native flow.
    static func applyHelperTermination(_ s: inout AgentSession, requestID: String) {
        guard s.approval?.requestID == requestID else {
            var queued = s.queuedApprovals ?? []
            queued.removeAll { $0.requestID == requestID }
            s.queuedApprovals = queued.isEmpty ? nil : queued
            return
        }
        switch s.approval?.state {
        case .pending, .sending, .none:
            // Helper gone before a decision reached it → native flow owns it.
            Self.releaseTransaction(&s, requestID: requestID, state: .fellBack)
        default:
            // Already answered (sent / providerOutputClosed / delivered).
            s.approval?.state = .helperTerminated
            s.pendingApprovalRequestID = nil
            s.requiresAttention = false
            if s.queuedApprovalCount > 0 { Self.finishCurrentTransaction(&s) }
        }
    }

    /// A provider progression signal is usable only when it carries the same
    /// provider-native tool or turn identity. Missing identifiers are not proof.
    static func providerProgressMatches(_ approval: PendingApproval,
                                        event: TerminalAgentEvent) -> Bool {
        if let toolUseID = approval.toolUseID, let eventToolUseID = event.toolUseID {
            return toolUseID == eventToolUseID
        }
        if let turnID = approval.turnID, let eventTurnID = event.turnID {
            return turnID == eventTurnID
        }
        return false
    }

    private static func toolNameMatches(_ approval: PendingApproval,
                                        event: TerminalAgentEvent) -> Bool {
        guard let approvalTool = approval.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let eventTool = event.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !approvalTool.isEmpty, !eventTool.isEmpty else { return false }
        return approvalTool.caseInsensitiveCompare(eventTool) == .orderedSame
    }

    private static func finishCurrentTransaction(_ s: inout AgentSession) {
        var queued = s.queuedApprovals ?? []
        s.approval = queued.isEmpty ? nil : queued.removeFirst()
        s.queuedApprovals = queued.isEmpty ? nil : queued
        s.pendingApprovalRequestID = s.approval?.requestID
        s.requiresAttention = s.approval?.isLive == true
        if s.approval != nil { s.status = .waitingForApproval }
    }

    private static func releaseTransaction(_ s: inout AgentSession, requestID: String,
                                           state: PendingApproval.ResponseState) {
        if s.approval?.requestID == requestID {
            s.approval?.state = state
            s.pendingApprovalRequestID = nil
            s.requiresAttention = false
            s.latestSummary = "Respond in Terminal"
            if s.status == .waitingForApproval { s.status = .running }
            return
        }
        var queued = s.queuedApprovals ?? []
        if let index = queued.firstIndex(where: { $0.requestID == requestID }) {
            queued[index].state = state
        }
        s.queuedApprovals = queued.isEmpty ? nil : queued
    }

    // MARK: Approvals

    /// The app session that owns a pending transaction (for the external "focus
    /// terminal" request). nil if the transaction is unknown/already resolved.
    func appSessionID(forTransaction tx: String) -> UUID? {
        pendingApprovals[tx]?.appSessionID
    }

    @discardableResult
    func respond(requestID: String, allow: Bool, message: String?) -> Bool {
        guard let connection = pendingApprovals[requestID] else { return false }
        guard Date() < connection.actionableUntil else {
            _ = releaseForFallback(requestID: requestID)
            return false
        }
        let decision = TerminalAgentDecision(requestID: connection.providerRequestID,
                                             transactionID: requestID,
                                             behavior: allow ? .allow : .deny, message: message)
        guard let data = TerminalAgentCodec.encodeLine(decision),
              writeAll(data, to: connection.clientFD) else {
            pendingApprovals[requestID] = nil
            return false
        }
        pendingApprovals[requestID] = nil
        return true
    }

    /// Release a still-blocked helper at the hybrid fallback deadline: tell it to
    /// stop waiting and return empty stdout (native prompt).
    @discardableResult
    func releaseForFallback(requestID: String) -> Bool {
        guard let connection = pendingApprovals[requestID] else { return false }
        let release = TerminalAgentDecision(
            requestID: connection.providerRequestID,
            transactionID: requestID,
            behavior: .deny,
            fallback: true
        )
        guard let data = TerminalAgentCodec.encodeLine(release),
              writeAll(data, to: connection.clientFD) else {
            pendingApprovals[requestID] = nil
            return false
        }
        pendingApprovals[requestID] = nil
        return true
    }

    private func releaseAllPendingToTerminal(reason: String) async {
        await releasePendingToTerminal(for: nil, reason: reason)
    }

    private func releasePendingToTerminal(for appSessionID: UUID?, reason: String) async {
        let pending = pendingApprovals.filter {
            appSessionID == nil || $0.value.appSessionID == appSessionID
        }
        guard !pending.isEmpty else { return }
        await MainActor.run { [store, stats] in
            stats.recordDecoded(type: reason, connectedTitle: "")
            for (transactionID, connection) in pending {
                store.update(id: connection.appSessionID) {
                    Self.releaseTransaction(
                        &$0,
                        requestID: transactionID,
                        state: .fellBack
                    )
                }
            }
        }
        for transactionID in pending.keys {
            _ = releaseForFallback(requestID: transactionID)
        }
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            while offset < data.count {
                let count = write(fd, base.advanced(by: offset), data.count - offset)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    #if DEBUG
    /// Test boundary for proving that identical provider-native IDs cannot
    /// cross-route between helper sockets. Production registration happens only
    /// in `ingest`.
    func registerPendingForTesting(
        transactionID: String,
        providerRequestID: String,
        appSessionID: UUID,
        clientFD: Int32
    ) {
        pendingApprovals[transactionID] = PendingApprovalConnection(
            clientFD: clientFD,
            providerRequestID: providerRequestID,
            appSessionID: appSessionID,
            actionableUntil: .distantFuture
        )
    }
    #endif

    // MARK: Offline sweep

    private func sweepLoop() async {
        while io.running {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            let now = Date()
            // Approval fallback / expiry sweep (runs frequently for a live countdown).
            let releaseRequestIDs: [String] = await MainActor.run { [store] in
                var releases: [String] = []
                for session in store.sessions {
                    store.update(id: session.id) {
                        releases.append(contentsOf: Self.expireTransactions(&$0, now: now))
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

    /// Expires current and queued requests independently. Expired queued entries
    /// are never promoted into an actionable card.
    static func expireTransactions(_ session: inout AgentSession, now: Date) -> [String] {
        var released: [String] = []
        if var queued = session.queuedApprovals {
            for index in queued.indices
            where queued[index].isLive && !queued[index].isActionable(now: now) {
                released.append(queued[index].requestID)
                queued[index].state = queued[index].nativePromptExpected ? .fellBack : .expired
            }
            session.queuedApprovals = queued.isEmpty ? nil : queued
        }
        if let approval = session.approval,
           approval.isLive,
           !approval.isActionable(now: now) {
            released.append(approval.requestID)
            releaseTransaction(
                &session,
                requestID: approval.requestID,
                state: approval.nativePromptExpected ? .fellBack : .expired
            )
        }
        return released
    }
}

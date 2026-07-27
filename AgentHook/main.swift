import Foundation
import Darwin

// notchdeck-agent-hook
//
// A tiny, fast helper invoked by Codex / Claude Code hooks. It reads the hook's
// JSON from stdin, forwards a sanitized event to NotchDeck's local bridge, and —
// only for permission requests — waits (bounded) for an Allow/Deny decision and
// prints the provider-specific JSON the CLI expects.
//
// Safety: if NotchDeck is not running, the socket is missing, or the wait times
// out, the helper prints nothing and exits 0 so the CLI falls back to its own
// native prompt. It never auto-approves or auto-denies, and never simulates keys.

struct Args {
    var provider: TerminalAgentProvider = .unknown
    var event: TerminalAgentEventType = .heartbeat
}

func parseArgs() -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--provider": if let v = it.next() { a.provider = TerminalAgentProvider.parse(v) }
        case "--event": if let v = it.next(), let e = TerminalAgentEventType(rawValue: v) { a.event = e }
        default: break
        }
    }
    return a
}

func readStdin() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

/// Minimal rotating helper log at ~/Library/Logs/NotchDeck/agent-hook.log.
/// Logs only non-sensitive metadata — never prompts, commands, tool input,
/// tokens, environment or credentials.
enum HookLog {
    static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent-hook.log")
    }
    static let maxBytes = 64 * 1024

    static func line(_ msg: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHDECK_AGENT_HOOK_TESTING"] == "1" {
            return
        }
        #endif
        let ts = ISO8601DateFormatter().string(from: Date())
        let entry = "\(ts) \(msg)\n"
        let u = url
        if let size = try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int,
           size > maxBytes, let data = try? Data(contentsOf: u) {
            try? data.suffix(maxBytes / 2).write(to: u, options: [.atomic])
        }
        if let handle = try? FileHandle(forWritingTo: u) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(to: u, atomically: true, encoding: .utf8)
        }
    }
}

func abbreviated(_ s: String) -> String { String(s.prefix(8)) }

/// Best-effort field extraction across Codex / Claude hook payloads.
func string(_ dict: [String: Any], _ keys: [String]) -> String? {
    for k in keys { if let v = dict[k] as? String, !v.isEmpty { return v } }
    return nil
}

func currentTTY() -> String? {
    guard let name = ttyname(STDIN_FILENO) ?? ttyname(STDOUT_FILENO) ?? ttyname(STDERR_FILENO)
    else { return nil }
    return String(cString: name)
}

/// Connect to the bridge socket. Returns fd or -1.
func connectSocket() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = TerminalAgentProtocol.socketURL().path
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { cstr in
            strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                    cstr, capacity - 1)
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let ok = withUnsafePointer(to: &addr) { p -> Int32 in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    if ok != 0 { close(fd); return -1 }
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    return fd
}

@discardableResult
func send(_ fd: Int32, _ event: TerminalAgentEvent) -> Bool {
    guard let data = TerminalAgentCodec.encodeLine(event) else { return false }
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

/// Wait up to `timeout` seconds for a decision line. Uses a 1s receive timeout
/// and loops until the deadline. Returns nil on timeout.
func awaitDecision(_ fd: Int32, transactionID: String, timeout: TimeInterval) -> TerminalAgentDecision? {
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    let deadline = Date().addingTimeInterval(timeout)
    var pending = Data()
    var buffer = [UInt8](repeating: 0, count: 2048)
    while Date() < deadline {
        let n = read(fd, &buffer, buffer.count)
        if n > 0 {
            pending.append(contentsOf: buffer[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: pending.startIndex..<nl)
                pending.removeSubrange(pending.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8),
                   let decision = TerminalAgentCodec.decodeDecision(line),
                   decision.transactionID == transactionID {
                    // A release means the app hit its fallback deadline: stop
                    // waiting and let the CLI show its native prompt (empty stdout).
                    if decision.fallback { return nil }
                    return decision
                }
            }
        } else if n == 0 {
            break // peer closed
        } else {
            // n < 0: timeout (EAGAIN) or error — keep looping until deadline.
            if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { break }
        }
    }
    return nil
}

/// Emit the provider-valid PermissionRequest decision JSON on stdout, using the
/// single audited encoder shared with the app/tests. stdout carries ONLY this
/// line; diagnostics go to the log file / stderr. stdout is flushed explicitly
/// (piped stdout is block-buffered) before the helper exits.
func emitDecision(provider: TerminalAgentProvider, decision: TerminalAgentDecision) {
    guard let adapter = AgentPermissionProviders.adapter(for: provider) else { return }
    FileHandle.standardOutput.write(
        adapter.response(behavior: decision.behavior, message: decision.message)
    )
    try? FileHandle.standardOutput.synchronize()
    try? FileHandle.standardOutput.close()
}

// MARK: Main

let args = parseArgs()
let payload = readStdin()

let sessionID = string(payload, ["session_id", "sessionId", "thread_id", "threadId"]) ?? "unknown"
let cwd = string(payload, ["cwd", "workingDirectory", "project_dir"]) ?? FileManager.default.currentDirectoryPath
let toolName = string(payload, ["tool_name", "toolName", "tool"])
let summary: String? = nil
let toolUseID = string(payload, ["tool_use_id", "toolUseId"])
let turnID = string(payload, ["turn_id", "turnId"])
// Real hook event name from the CLI payload (for logging accuracy).
let hookEventName = string(payload, ["hook_event_name", "hookEventName"]) ?? args.event.rawValue
let parsedPermission: AgentPermissionRequest?
if let adapter = AgentPermissionProviders.adapter(for: args.provider) {
    parsedPermission = try? adapter.parse(payload)
} else {
    parsedPermission = nil
}
let isDecisionHook = (args.event == .permissionRequested)
// Unsupported or malformed decision hooks fail safely with empty stdout. They
// must never become functional approval cards using a guessed identity/schema.
guard !isDecisionHook || parsedPermission != nil else {
    HookLog.line("permission parse failed → native fallback exit 0")
    exit(0)
}
let requestID = parsedPermission?.requestID
    ?? toolUseID
    ?? string(payload, ["request_id", "requestId"])
    ?? UUID().uuidString
let transactionID = isDecisionHook ? UUID().uuidString : nil

HookLog.line("event=\(hookEventName) provider=\(args.provider.cliName) session=\(abbreviated(sessionID))")

var event = TerminalAgentEvent(
    type: args.event,
    provider: args.provider,
    sessionID: sessionID,
    cwd: cwd,
    timestamp: Date().timeIntervalSince1970,
    turnID: turnID,
    toolName: toolName,
    summary: summary,
    pid: getpid(),
    ppid: getppid(),
    tty: currentTTY(),
    terminalApp: ProcessInfo.processInfo.environment["TERM_PROGRAM"],
    requestID: isDecisionHook ? requestID : nil,
    transactionID: transactionID,
    toolUseID: toolUseID)

let fd = connectSocket()
if fd < 0 {
    // NotchDeck not available → stay out of the way; CLI shows native prompt.
    HookLog.line("socket connect FAILED → native fallback exit 0")
    exit(0)
}
HookLog.line("socket connected")
send(fd, event)

if isDecisionHook {
    // Block on the SAME live connection until a decision arrives (or the wait
    // exceeds the helper hard deadline). The deadline is longer than the app's UI
    // fallback so the user has time to choose; the app sends an explicit release
    // at its fallback deadline.
    if let transactionID,
       let decision = awaitDecision(fd, transactionID: transactionID,
                                    timeout: HookTimeouts.helperHardDeadlineSeconds) {
        HookLog.line("decision received: \(decision.behavior.rawValue)")
        // Write ONLY the provider response to the original stdout, flush it, then
        // notify the app that the bytes were written (NOT that the provider
        // accepted them). No provider-facing descriptor is kept open afterwards.
        emitDecision(provider: args.provider, decision: decision)
        _ = send(fd, TerminalAgentEvent(type: .responseWritten, provider: args.provider,
                                        sessionID: sessionID, timestamp: Date().timeIntervalSince1970,
                                        requestID: requestID, transactionID: transactionID,
                                        toolUseID: toolUseID))
        _ = send(fd, TerminalAgentEvent(type: .helperExited, provider: args.provider,
                                        sessionID: sessionID, timestamp: Date().timeIntervalSince1970,
                                        requestID: requestID, transactionID: transactionID,
                                        toolUseID: toolUseID))
    } else {
        // Timeout / release → print nothing → CLI resumes its native permission
        // flow. The helper does not wait for any further app message.
        HookLog.line("no decision → native fallback (empty stdout)")
    }
}
close(fd)
HookLog.line("exit 0")
exit(0)

import Foundation

/// DEBUG-only, in-memory diagnostics for the permission-approval transaction and
/// terminal-tab matching. It records ONLY non-sensitive correlation metadata —
/// provider, abbreviated session id, request correlation id, canonical TTY and
/// state transitions. It NEVER stores prompts, command arguments, secrets, full
/// filesystem paths or environment values. In Release every entry point is a
/// no-op and nothing is retained or shown.
final class AgentApprovalDiagnostics: @unchecked Sendable {
    static let shared = AgentApprovalDiagnostics()

    struct Entry { var time: Date; var line: String }
    private let lock = NSLock()
    private var _entries: [Entry] = []
    private let maxEntries = 200
    var entries: [Entry] { lock.lock(); defer { lock.unlock() }; return _entries }

    private func append(_ line: String) {
        #if DEBUG
        lock.lock()
        _entries.append(Entry(time: Date(), line: line))
        if _entries.count > maxEntries { _entries.removeFirst(_entries.count - maxEntries) }
        lock.unlock()
        Log.agents.debug("approval-diag \(line, privacy: .public)")
        #endif
    }

    private static func abbrev(_ s: String) -> String { String(s.prefix(8)) }

    // MARK: Recording (no-ops in Release)

    static func record(session: AgentSession, requestID: String, transition: String) {
        #if DEBUG
        shared.append("provider=\(session.provider.rawValue) session=\(abbrev(session.providerSessionID ?? session.id.uuidString)) req=\(abbrev(requestID)) tty=\(session.terminalTTY ?? "—") :: \(transition)")
        #endif
    }

    static func record(sessionID: UUID, requestID: String, transition: String) {
        #if DEBUG
        shared.append("session=\(abbrev(sessionID.uuidString)) req=\(abbrev(requestID)) :: \(transition)")
        #endif
    }

    static func recordTerminal(_ line: String) {
        #if DEBUG
        shared.append("terminal :: \(line)")
        #endif
    }

    static func recordProcess(snapshot: AgentProcessSnapshot, session: AgentSession?) {
        #if DEBUG
        let identity = snapshot.identity
        let ancestry = MacProcessAncestry.identities(from: identity.pid)
            .dropFirst()
            .prefix(16)
            .map { "\($0.pid)@\($0.startSeconds).\($0.startMicroseconds)" }
            .joined(separator: ">")
        let appSession = session.map { abbrev($0.id.uuidString) } ?? "unmatched"
        let providerSession = session?.providerSessionID.map(abbrev) ?? "—"
        shared.append(
            "process pid=\(identity.pid) start=\(identity.startSeconds).\(identity.startMicroseconds) "
                + "exe=\(snapshot.executableBasename) classification=\(snapshot.classification.rawValue) "
                + "provider=\(snapshot.provider.rawValue) ppid=\(snapshot.parentPID) "
                + "ancestry=\(ancestry.isEmpty ? "—" : ancestry) "
                + "tty=\(snapshot.controllingTTY?.canonicalPath ?? "—") "
                + "ttySource=\(snapshot.controllingTTY?.source.rawValue ?? "—") "
                + "discovered=\(snapshot.discoveredAt.timeIntervalSince1970) "
                + "appSession=\(appSession) providerSession=\(providerSession)"
        )
        #endif
    }

    static func recordHookDecodeFailure() {
        #if DEBUG
        shared.append("hook decoded=false payload=redacted")
        #endif
    }

    static func recordHook(event: TerminalAgentEvent, decoded: Bool,
                           correlation: AgentHookCorrelationConfidence?) {
        #if DEBUG
        shared.append(
            "hook event=\(event.type.rawValue) decoded=\(decoded) provider=\(event.provider.rawValue) "
                + "helperPid=\(event.pid.map(String.init) ?? "—") "
                + "providerSession=\(abbrev(event.sessionID)) "
                + "correlation=\(correlation?.rawValue ?? "none")"
        )
        #endif
    }

    /// A copy-ready snapshot for the Debug "Copy Diagnostics" action.
    func snapshot() -> String {
        #if DEBUG
        let fmt = ISO8601DateFormatter()
        return entries.map { "\(fmt.string(from: $0.time)) \($0.line)" }.joined(separator: "\n")
        #else
        return ""
        #endif
    }
}

/// A readable trail of agent permission requests at
/// ~/Library/Logs/NotchDeck/agent-requests.log: who asked (agent + folder name),
/// the agent's own question, the action (sanitized, shortened) and how it ended
/// (answered here, released to the terminal, or the agent stopped waiting).
/// Lets a request that looks "phantom" be checked against the agent's own logs.
/// Never stores full paths, environment, or secrets (sanitized like the UI).
enum ApprovalLog {
    static let maxBytes = 256 * 1024
    private static let queue = DispatchQueue(label: "notchdeck.approval-log", qos: .utility)

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchDeck/agent-requests.log")
    }

    static func requestLine(transactionID: String, provider: AgentProviderKind, projectPath: String,
                            toolName: String?, reason: String?, action: String) -> String {
        let name: String
        switch provider {
        case .claudeCode: name = "Claude Code"
        case .codex: name = "Codex"
        case .external: name = "Agent"
        }
        let project = URL(fileURLWithPath: projectPath).lastPathComponent
        let who = projectPath.isEmpty || project.isEmpty ? name : "\(name) · \(project)"
        var line = "REQUEST tx=\(transactionID.prefix(8)) \(who) tool=\(toolName ?? "?")"
        if let reason, !reason.isEmpty { line += " \"\(reason)\"" }
        let shortAction = action.count > 120 ? String(action.prefix(119)) + "…" : action
        line += " action: \(shortAction)"
        return line
    }

    static func outcomeLine(transactionID: String, outcome: String) -> String {
        "OUTCOME tx=\(transactionID.prefix(8)) \(outcome)"
    }

    static func write(_ line: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        let stamp = Date()
        queue.async {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let entry = "\(f.string(from: stamp)) \(line)\n"
            let u = url
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
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
}

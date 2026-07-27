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

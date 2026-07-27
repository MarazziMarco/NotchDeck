import Foundation

/// Tracks live `ManagedProcess` instances by session id so the coordinator can
/// interrupt exactly the processes NotchDeck launched — never external ones.
actor AgentProcessTable {
    static let shared = AgentProcessTable()

    private var processes: [UUID: ManagedProcess] = [:]

    func register(sessionID: UUID, process: ManagedProcess) {
        processes[sessionID] = process
    }

    func process(for sessionID: UUID) -> ManagedProcess? {
        processes[sessionID]
    }

    /// Exact live PID for each session-owned Process object. The authoritative
    /// scanner combines this ephemeral mapping with the kernel start timestamp
    /// before persisting a process identity.
    func liveProcessIDs() async -> [UUID: Int32] {
        let entries = processes
        var result: [UUID: Int32] = [:]
        for (sessionID, process) in entries {
            if let pid = await process.livePID {
                result[sessionID] = pid
            }
        }
        return result
    }

    func writeLine(_ text: String, to sessionID: UUID) async {
        await processes[sessionID]?.writeLine(text)
    }

    func interrupt(sessionID: UUID) async {
        guard let process = processes[sessionID] else { return }
        await process.terminate()
        processes[sessionID] = nil
    }

    func remove(sessionID: UUID) {
        processes[sessionID] = nil
    }
}

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

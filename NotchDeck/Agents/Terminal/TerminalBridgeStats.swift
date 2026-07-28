import Foundation
import Combine
import Darwin

/// Observable, main-actor runtime counters the bridge updates so Settings can
/// show live diagnostics and make it impossible for a bridge event to disappear
/// silently.
@MainActor
final class TerminalBridgeStats: ObservableObject {
    @Published var isListening = false
    @Published var startedAt: Date?
    @Published var socketPath: String = TerminalAgentProtocol.socketURL().path
    @Published var lastLifecycleError: String?

    @Published var rawConnections = 0
    @Published var decodedEvents = 0
    @Published var rejectedEvents = 0
    @Published var lastDecodeError: String = "—"

    @Published var lastEventAt: Date?
    @Published var lastEventType: String = "—"
    @Published var lastConnectedTitle: String = "—"

    // Store / UI observability
    @Published var storeCount = 0
    @Published var connectedCount = 0
    @Published var externalCount = 0
    @Published var uiObservedCount = 0
    @Published var lastUIRefreshAt: Date?

    func markListening(_ on: Bool) {
        isListening = on
        if on && startedAt == nil { startedAt = Date() }
    }

    func recordLifecycleFailure(_ message: String?) {
        lastLifecycleError = message
    }

    func recordConnection() { rawConnections += 1 }

    func recordDecoded(type: String, connectedTitle: String?) {
        decodedEvents += 1
        lastEventAt = Date()
        lastEventType = type
        if let connectedTitle, !connectedTitle.isEmpty { lastConnectedTitle = connectedTitle }
    }

    func recordRejected(_ reason: String) {
        rejectedEvents += 1
        lastDecodeError = reason
    }

    func syncStoreCounts(total: Int, connected: Int, external: Int) {
        storeCount = total; connectedCount = connected; externalCount = external
    }

    func noteUIRefresh(count: Int) {
        uiObservedCount = count
        lastUIRefreshAt = Date()
    }

    var lastEventDescription: String {
        guard let at = lastEventAt else { return "none yet" }
        return "\(lastEventType) · \(RelativeDateTimeFormatter().localizedString(for: at, relativeTo: Date()))"
    }

    /// Owner uid + octal permissions of the socket file (security check).
    var socketOwnerPermissions: String {
        var st = stat()
        guard stat(socketPath, &st) == 0 else { return "no socket" }
        let perms = String(st.st_mode & 0o777, radix: 8)
        return "uid \(st.st_uid), mode 0\(perms)"
    }
}

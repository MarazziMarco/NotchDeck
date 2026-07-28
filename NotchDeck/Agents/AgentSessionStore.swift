import Foundation
import Combine

/// Observable store of all known sessions (managed + external), sorted for the
/// Agents face. Persists managed session metadata locally (never credentials).
@MainActor
final class AgentSessionStore: ObservableObject, LiveActivitySource {
    @Published private(set) var sessions: [AgentSession] = []

    // Compact live-activity configuration (set from settings).
    var compactDisplay: CompactAgentsDisplay = .activeCount {
        didSet {
            if compactDisplay != oldValue { objectWillChange.send() }
        }
    }
    var compactAccent: AgentCompactAccent = .orange {
        didSet {
            if compactAccent != oldValue { objectWillChange.send() }
        }
    }
    var recentLimit: RecentSessionLimit = .ten
    var showFailed: Bool = true
    var showExternal: Bool = true
    var completionActivitySeconds: Double = 8
    /// When the Agents module is disabled, the store keeps its data (history is
    /// preserved) but contributes NO compact live activity to the notch.
    var compactSuppressed: Bool = false {
        didSet {
            if compactSuppressed != oldValue { objectWillChange.send() }
        }
    }

    private let store: JSONFileStore<[AgentSession]>

    init(fileName: String = "agent-sessions.json") {
        self.store = JSONFileStore(fileName: fileName)
        // Restore managed sessions; mark any left "running" as interrupted since
        // their processes did not survive the last quit.
        let restored = (store.load() ?? []).map { session -> AgentSession in
            var s = session
            if s.isManaged, [.running, .starting, .waitingForApproval, .waitingForInput].contains(s.status) {
                s.status = .interrupted
                s.requiresAttention = false
            }
            return s
        }
        self.sessions = restored
    }

    /// Sessions ordered by attention rank, then most-recent activity.
    var orderedSessions: [AgentSession] {
        sessions.sorted { lhs, rhs in
            if lhs.status.attentionRank != rhs.status.attentionRank {
                return lhs.status.attentionRank < rhs.status.attentionRank
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    var activeCount: Int { activeSessions.count }

    var attentionSession: AgentSession? {
        orderedSessions.first { $0.status.requiresAttention }
    }

    var runningSessions: [AgentSession] {
        sessions.filter { [.running, .starting].contains($0.status) }
    }

    // MARK: Active / Recent (terminal-presence driven)

    func bucket(_ s: AgentSession, now: Date = Date()) -> AgentBucket {
        AgentSessionFilter.bucket(s)
    }

    /// Sessions to show in Active, attention-first.
    var activeSessions: [AgentSession] {
        let now = Date()
        return orderedSessions.filter { bucket($0, now: now) == .active }
    }

    /// Recent (completed/failed/interrupted/closed), newest first, capped by the
    /// configured limit and filters.
    var recentSessions: [AgentSession] {
        let now = Date()
        var items = sessions
            .filter { bucket($0, now: now) == .recent }
            .filter { showFailed || $0.status != .failed }
            .filter { showExternal || ($0.isBridgeConnected || $0.isManaged) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        let limit = recentLimit.limit
        if limit == 0 { return [] }
        if items.count > limit { items = Array(items.prefix(limit)) }
        return items
    }

    // MARK: LiveActivitySource

    nonisolated func currentActivity() -> ResolvedActivity? {
        MainActor.assumeIsolated {
            // Agents disabled → no compact agent state ever reaches the notch.
            guard !compactSuppressed else { return nil }
            let active = activeSessions
            let inputs = CompactAgentIndicatorInputs.resolve(
                activeSessions: active,
                displayPreference: compactDisplay
            )
            let model = CompactAgentIndicatorModel.resolve(inputs)
            return CompactAgentActivityFactory.make(
                for: CompactAgentPresentation(state: model, providers: inputs.providers),
                accent: compactAccent
            )
        }
    }

    func upsert(_ session: AgentSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persistManaged()
    }

    func update(id: UUID, _ transform: (inout AgentSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        transform(&sessions[idx])
        persistManaged()
    }

    func session(id: UUID) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        persistManaged()
    }

    /// Clear the Recent bucket (completed/failed/closed). Active sessions stay.
    func clearRecent() {
        let now = Date()
        sessions.removeAll { bucket($0, now: now) == .recent }
        persistManaged()
    }

    /// Replace only the plain external (window-scanned) sessions with a fresh
    /// scan. Managed sessions AND hook-connected bridge sessions are preserved —
    /// a Connected session must never be wiped by the Accessibility scan.
    func replaceExternal(_ external: [AgentSession]) {
        sessions.removeAll {
            !$0.isManaged && !$0.isBridgeConnected && $0.processIdentity == nil
        }
        // Process-discovered and hook-connected sessions are authoritative.
        // A compatibility Accessibility scan may observe the same Terminal
        // window, but must not create a second card for it.
        let authoritative = sessions.filter {
            $0.processIdentity != nil || $0.isBridgeConnected
        }
        let filtered = external.filter { ext in
            !authoritative.contains {
                AgentSessionMerge.externalDuplicatesConnected(external: ext, connected: $0)
            }
        }
        sessions.append(contentsOf: filtered)
    }

    /// Reconcile the authoritative local process scan without disturbing
    /// managed, hook-only, or window-only compatibility records.
    func replaceDiscoveredProcesses(
        _ snapshots: [AgentProcessSnapshot],
        now: Date = Date(),
        managedProcessIDs: [UUID: Int32] = [:]
    ) {
        sessions = AgentProcessReconciler.reconcile(
            existing: sessions,
            snapshots: snapshots,
            now: now,
            managedProcessIDs: managedProcessIDs
        )
        #if DEBUG
        for snapshot in snapshots {
            AgentApprovalDiagnostics.recordProcess(
                snapshot: snapshot,
                session: sessions.first { $0.processIdentity == snapshot.identity }
            )
        }
        #endif
        persistManaged()
    }

    private func persistManaged() {
        store.save(sessions.filter { $0.isManaged })
    }
}

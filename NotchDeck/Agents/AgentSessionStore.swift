import Foundation
import Combine

/// Observable store of all known sessions (managed + external), sorted for the
/// Agents face. Persists managed session metadata locally (never credentials).
@MainActor
final class AgentSessionStore: ObservableObject, LiveActivitySource {
    @Published private(set) var sessions: [AgentSession] = []

    // Compact live-activity configuration (set from settings).
    var compactDisplay: CompactAgentsDisplay = .activeCount
    var compactAccent: AgentCompactAccent = .orange
    var recentLimit: RecentSessionLimit = .ten
    var showFailed: Bool = true
    var showExternal: Bool = true
    var completionActivitySeconds: Double = 8
    /// When the Agents module is disabled, the store keeps its data (history is
    /// preserved) but contributes NO compact live activity to the notch.
    var compactSuppressed: Bool = false

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
        AgentSessionFilter.bucket(presence: s.terminalPresence, status: s.status,
                                  isBridgeConnected: s.isBridgeConnected,
                                  isManaged: s.isManaged,
                                  hasExternalWindow: s.externalBundleID != nil)
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
            let now = Date()
            let active = activeSessions
            // Genuine approval requires a LIVE PendingApproval (not mere activity).
            let approvalSession = active.first { $0.hasLiveApproval }
            let inputSession = active.first { $0.status == .waitingForInput }
            let running = active.filter { [.running, .starting].contains($0.status) }
            let completed = orderedSessions.first {
                $0.status == .completed && now.timeIntervalSince($0.lastActivityAt) < completionActivitySeconds
            }

            let elapsed = running.first.map { Self.elapsed($0) }
            guard let model = AgentCompactActivity.resolve(
                activeVendors: running.map(\.vendor),
                approvalVendor: approvalSession?.vendor,
                inputVendor: inputSession?.vendor,
                completedProject: completed?.projectName,
                display: compactDisplay,
                elapsedText: elapsed) else { return nil }

            let ordinaryTint: StatusTint = compactAccent == .orange ? .agentActive : .neutral
            let glyph = model.glyphVendors.first?.fallbackSymbol ?? "cpu"
            let badge = model.extraCount > 0 ? model.extraCount : nil

            switch model.kind {
            case .approval:
                // Provider logo (left) + concise semantic label (right), chosen by
                // width — never a truncated fragment. Includes the fallback
                // countdown when known.
                let vendor = approvalSession?.vendor ?? .unknown
                let remaining = approvalSession?.approval?.fallbackRemaining(now: now).map { Int($0.rounded(.up)) }
                let label = CompactApprovalLabel.text(vendor: vendor, remainingSeconds: remaining, availableWidth: 76)
                return ResolvedActivity(
                    id: "agents", priority: .approval,
                    slot: WingSlot(tint: .approval, pulse: true, providerVendor: vendor),
                    preferredWing: .leading, attention: true,
                    tapTarget: .face(.agents), exclusive: true, exclusiveLabel: label)
            case .input:
                return ResolvedActivity(
                    id: "agents", priority: .input,
                    slot: WingSlot(symbol: glyph, tint: .attention, pulse: true),
                    preferredWing: .leading, attention: true,
                    tapTarget: .face(.agents), exclusive: true, exclusiveLabel: "Input needed")
            case .active:
                return ResolvedActivity(
                    id: "agents", priority: .agentsRunning,
                    slot: WingSlot(symbol: glyph, text: model.text, tint: ordinaryTint,
                                   pulse: true, badge: badge),
                    preferredWing: .trailing, tapTarget: .face(.agents))
            case .completed:
                return ResolvedActivity(
                    id: "agents", priority: .agentsRunning,
                    slot: WingSlot(symbol: "checkmark.circle.fill",
                                   text: String(model.text.prefix(16)), tint: .success),
                    preferredWing: .trailing, tapTarget: .face(.agents))
            }
        }
    }

    private static func elapsed(_ s: AgentSession) -> String {
        let secs = Int(Date().timeIntervalSince(s.startedAt))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h"
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
        sessions.removeAll { !$0.isManaged && !$0.isBridgeConnected }
        // Don't re-add a scanned window that duplicates a connected session
        // (same terminal app + title).
        let connected = sessions.filter { $0.isBridgeConnected }
        // Merge: drop a scanned window that duplicates a connected session by
        // PID / TTY / project title — never show duplicates.
        let filtered = external.filter { ext in
            !connected.contains { AgentSessionMerge.externalDuplicatesConnected(external: ext, connected: $0) }
        }
        sessions.append(contentsOf: filtered)
    }

    private func persistManaged() {
        store.save(sessions.filter { $0.isManaged })
    }
}

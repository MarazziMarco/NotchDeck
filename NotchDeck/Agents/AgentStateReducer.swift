import Foundation

/// Pure reduction of a normalized `AgentEvent` onto an `AgentSession`. Kept
/// separate from I/O so status transitions are fully unit-testable.
enum AgentStateReducer {

    static func reduce(_ session: AgentSession, event: AgentEvent, now: Date = Date()) -> AgentSession {
        var s = session
        s.lastActivityAt = now
        switch event {
        case .started(let providerID):
            if let providerID { s.providerSessionID = providerID }
            if s.status == .starting { s.status = .running }
            s.requiresAttention = false

        case .status(let status):
            s.status = status
            s.requiresAttention = status.requiresAttention

        case .message(_, let text):
            s.latestSummary = String(text.prefix(160))
            if s.status == .starting { s.status = .running }

        case .toolUse(let name, _):
            s.latestSummary = "Using \(name)"
            s.status = .running

        case .approvalRequested(let summary):
            s.status = .waitingForApproval
            s.requiresAttention = true
            s.latestSummary = summary

        case .completed(let summary):
            s.status = .completed
            s.requiresAttention = false
            if let summary, !summary.isEmpty { s.latestSummary = String(summary.prefix(160)) }

        case .failed(let reason):
            s.status = .failed
            s.requiresAttention = true
            s.latestSummary = String(reason.prefix(160))

        case .log:
            break   // logs don't change session state
        }
        return s
    }
}

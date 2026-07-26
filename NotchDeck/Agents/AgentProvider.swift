import Foundation

/// A stream of normalized events from a running managed session.
typealias AgentEventStream = AsyncStream<AgentEvent>

/// Adapter contract for a coding-agent backend. Adapters normalize only the
/// capabilities the installed CLI actually exposes — they never pretend two
/// providers have identical APIs.
protocol AgentProvider: AnyObject {
    var kind: AgentProviderKind { get }

    func detectAvailability() async -> ProviderAvailability

    /// Start a managed session. The returned stream yields normalized events
    /// until the session terminates; the session record is delivered via the
    /// first `.started` event's provider id being written back by the caller.
    func startSession(projectURL: URL,
                      prompt: String,
                      configuration: AgentLaunchConfiguration) async throws -> (AgentSession, AgentEventStream)

    /// Send a follow-up message to a managed session (resume-based for CLIs
    /// that don't hold a long-lived stream).
    func send(message: String, to session: AgentSession) async throws -> AgentEventStream

    func interrupt(_ session: AgentSession) async throws
    func resume(_ session: AgentSession) async throws -> AgentEventStream
    func refresh(_ session: AgentSession) async throws -> AgentSession
}

extension AgentProvider {
    func refresh(_ session: AgentSession) async throws -> AgentSession { session }
}

import Foundation

/// A fake provider that scripts a realistic event sequence without launching any
/// process or consuming credits. Used by tests and SwiftUI previews.
final class MockAgentProvider: AgentProvider {
    let kind: AgentProviderKind
    var scriptedAvailability: ProviderAvailability
    /// Events to emit, with a delay (seconds) before each.
    var script: [(delay: Double, event: AgentEvent)]

    init(kind: AgentProviderKind = .codex,
         availability: ProviderAvailability = ProviderAvailability(
            isInstalled: true, executablePath: "/usr/local/bin/mock",
            version: "mock 1.0", authenticated: true, detail: nil),
         script: [(delay: Double, event: AgentEvent)]? = nil) {
        self.kind = kind
        self.scriptedAvailability = availability
        self.script = script ?? MockAgentProvider.defaultScript
    }

    static let defaultScript: [(delay: Double, event: AgentEvent)] = [
        (0.0, .started(providerSessionID: "mock-thread-1")),
        (0.1, .status(.running)),
        (0.1, .message(role: "assistant", text: "Analyzing the project…")),
        (0.2, .toolUse(name: "read_file", summary: "README.md")),
        (0.2, .message(role: "assistant", text: "Done. Everything looks good.")),
        (0.1, .completed(summary: "Completed successfully")),
    ]

    func detectAvailability() async -> ProviderAvailability { scriptedAvailability }

    func startSession(projectURL: URL,
                      prompt: String,
                      configuration: AgentLaunchConfiguration) async throws -> (AgentSession, AgentEventStream) {
        let session = AgentSession(provider: kind,
                                   providerSessionID: "mock-thread-1",
                                   title: prompt.isEmpty ? "Mock session" : prompt,
                                   projectPath: projectURL.path,
                                   status: .starting)
        return (session, makeStream())
    }

    func send(message: String, to session: AgentSession) async throws -> AgentEventStream {
        makeStream()
    }

    func interrupt(_ session: AgentSession) async throws {}
    func resume(_ session: AgentSession) async throws -> AgentEventStream { makeStream() }

    private func makeStream() -> AgentEventStream {
        AsyncStream { continuation in
            let task = Task {
                for step in script {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
                    continuation.yield(step.event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

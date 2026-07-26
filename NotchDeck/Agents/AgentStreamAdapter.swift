import Foundation

/// Bridges a `ManagedProcess` line stream into a normalized `AgentEvent` stream
/// using a per-line parser. Handles terminal events: if the process exits
/// without a completion/failure, a synthetic one is emitted based on exit code.
enum AgentStreamAdapter {

    /// - Parameters:
    ///   - process: an already-created (not yet launched) managed process.
    ///   - launch: closure that launches `process` and returns its line stream.
    ///   - parse: per-line parser (Codex or Claude).
    ///   - log: rotating log to append raw lines to.
    static func run(process: ManagedProcess,
                    launch: @escaping () async throws -> AsyncStream<ProcessLine>,
                    parse: @escaping (String) -> [AgentEvent],
                    log: RotatingLog?) -> AsyncStream<AgentEvent> {
        AsyncStream<AgentEvent> { continuation in
            let task = Task {
                do {
                    let lines = try await launch()
                    var sawTerminal = false
                    for await line in lines {
                        switch line {
                        case .stdout(let text):
                            log?.append(text)
                            for event in parse(text) {
                                if case .completed = event { sawTerminal = true }
                                if case .failed = event { sawTerminal = true }
                                continuation.yield(event)
                            }
                        case .stderr(let text):
                            log?.append("[stderr] " + text)
                            // stderr is rarely JSON; keep it as a log line only.
                            continuation.yield(.log(text))
                        case .terminated(let code):
                            if !sawTerminal {
                                if code == 0 {
                                    continuation.yield(.completed(summary: nil))
                                } else {
                                    continuation.yield(.failed(reason: "Process exited with code \(code)"))
                                }
                            }
                            continuation.finish()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(reason: error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

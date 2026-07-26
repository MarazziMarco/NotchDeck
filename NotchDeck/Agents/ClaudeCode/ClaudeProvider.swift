import Foundation

/// Claude Code adapter using the CLI's programmatic mode:
/// `claude -p --output-format stream-json --verbose [--permission-mode …]`.
/// Reuses the user's existing CLI authentication — never stores API keys, never
/// defaults to `--dangerously-skip-permissions`.
final class ClaudeProvider: AgentProvider {
    let kind: AgentProviderKind = .claudeCode

    private let resolver: ExecutableResolver
    private let logMaxBytes: Int
    private let loggingEnabled: Bool

    init(overridePath: String? = nil, logMaxBytes: Int = 512 * 1024, loggingEnabled: Bool = true) {
        self.resolver = ExecutableResolver(overridePath: overridePath)
        self.logMaxBytes = logMaxBytes
        self.loggingEnabled = loggingEnabled
    }

    func detectAvailability() async -> ProviderAvailability {
        guard let path = resolver.resolve("claude") else { return .notInstalled }
        let version = ExecutableResolver.version(of: path)
        let credFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let authenticated = FileManager.default.fileExists(atPath: credFile.path)
            || FileManager.default.fileExists(atPath: configDir.path)
        return ProviderAvailability(isInstalled: true, executablePath: path,
                                    version: version, authenticated: authenticated,
                                    detail: authenticated ? nil : "Run `claude` once to sign in.")
    }

    func startSession(projectURL: URL,
                      prompt: String,
                      configuration: AgentLaunchConfiguration) async throws -> (AgentSession, AgentEventStream) {
        guard let path = resolver.resolve("claude") else {
            throw NotchDeckError.executableNotFound(tool: "claude")
        }
        try validate(projectURL)

        // We assign the session id up front so we can resume deterministically.
        let session = AgentSession(provider: .claudeCode,
                                   providerSessionID: UUID().uuidString,
                                   title: prompt.isEmpty ? "Claude session" : String(prompt.prefix(48)),
                                   projectPath: projectURL.path,
                                   status: .starting)

        var args = ["-p",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--permission-mode", configuration.permissionMode.claudeFlag,
                    "--session-id", session.providerSessionID!]
        if let model = configuration.model { args += ["--model", model] }
        args.append(prompt)

        let stream = makeStream(path: path, args: args, cwd: projectURL,
                                env: configuration.extraEnvironment, sessionID: session.id)
        return (session, stream)
    }

    func send(message: String, to session: AgentSession) async throws -> AgentEventStream {
        guard let path = resolver.resolve("claude") else {
            throw NotchDeckError.executableNotFound(tool: "claude")
        }
        var args = ["-p", "--output-format", "stream-json", "--verbose"]
        if let sid = session.providerSessionID {
            args += ["--resume", sid]
        }
        args.append(message)
        return makeStream(path: path, args: args,
                          cwd: URL(fileURLWithPath: session.projectPath),
                          env: [:], sessionID: session.id)
    }

    func interrupt(_ session: AgentSession) async throws {
        throw NotchDeckError.unsupportedOperation("interrupt handled by coordinator")
    }

    func resume(_ session: AgentSession) async throws -> AgentEventStream {
        try await send(message: "continue", to: session)
    }

    private func makeStream(path: String, args: [String], cwd: URL,
                            env: [String: String], sessionID: UUID) -> AgentEventStream {
        let process = ManagedProcess()
        let log = RotatingLog(sessionID: sessionID, maxBytes: logMaxBytes, enabled: loggingEnabled)
        return AgentStreamAdapter.run(
            process: process,
            launch: {
                await AgentProcessTable.shared.register(sessionID: sessionID, process: process)
                return try await process.launch(executablePath: path, arguments: args,
                                                workingDirectory: cwd, environment: env)
            },
            parse: ClaudeEventParser.parse,
            log: log)
    }

    private func validate(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NotchDeckError.invalidProjectPath(url.path)
        }
    }
}

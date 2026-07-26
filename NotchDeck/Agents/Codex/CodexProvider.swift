import Foundation

/// Codex adapter. Uses `codex exec --json` (documented, stable) for structured
/// managed sessions, parsing the thread/turn/item JSONL envelope. The Codex
/// app-server path is documented as a future upgrade in AGENT_INTEGRATIONS.md.
final class CodexProvider: AgentProvider {
    let kind: AgentProviderKind = .codex

    private let resolver: ExecutableResolver
    private let logMaxBytes: Int
    private let loggingEnabled: Bool

    init(overridePath: String? = nil, logMaxBytes: Int = 512 * 1024, loggingEnabled: Bool = true) {
        self.resolver = ExecutableResolver(overridePath: overridePath)
        self.logMaxBytes = logMaxBytes
        self.loggingEnabled = loggingEnabled
    }

    func detectAvailability() async -> ProviderAvailability {
        guard let path = resolver.resolve("codex") else { return .notInstalled }
        let version = ExecutableResolver.version(of: path)
        // Auth is detected only by the presence of the local auth file — we never
        // read or transmit its contents.
        let authFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        let authenticated = FileManager.default.fileExists(atPath: authFile.path)
        return ProviderAvailability(isInstalled: true, executablePath: path,
                                    version: version, authenticated: authenticated,
                                    detail: nil)
    }

    func startSession(projectURL: URL,
                      prompt: String,
                      configuration: AgentLaunchConfiguration) async throws -> (AgentSession, AgentEventStream) {
        guard let path = resolver.resolve("codex") else {
            throw NotchDeckError.executableNotFound(tool: "codex")
        }
        try validate(projectURL)

        let session = AgentSession(provider: .codex,
                                   title: prompt.isEmpty ? "Codex session" : String(prompt.prefix(48)),
                                   projectPath: projectURL.path,
                                   status: .starting)
        var args = ["exec", "--json", "--skip-git-repo-check"]
        if let model = configuration.model { args += ["-m", model] }
        args.append(prompt)

        let stream = makeStream(path: path, args: args, cwd: projectURL,
                                env: configuration.extraEnvironment, sessionID: session.id)
        return (session, stream)
    }

    func send(message: String, to session: AgentSession) async throws -> AgentEventStream {
        guard let path = resolver.resolve("codex") else {
            throw NotchDeckError.executableNotFound(tool: "codex")
        }
        // Follow-ups resume the recorded thread when available.
        var args = ["exec", "--json", "--skip-git-repo-check"]
        if let threadID = session.providerSessionID {
            args = ["exec", "resume", threadID, "--json", "--skip-git-repo-check"]
        }
        args.append(message)
        return makeStream(path: path, args: args,
                          cwd: URL(fileURLWithPath: session.projectPath),
                          env: [:], sessionID: session.id)
    }

    func interrupt(_ session: AgentSession) async throws {
        // Managed processes are tracked and terminated by AgentCoordinator.
        throw NotchDeckError.unsupportedOperation("interrupt handled by coordinator")
    }

    func resume(_ session: AgentSession) async throws -> AgentEventStream {
        try await send(message: "", to: session)
    }

    // MARK: Helpers

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
            parse: CodexEventParser.parse,
            log: log)
    }

    private func validate(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NotchDeckError.invalidProjectPath(url.path)
        }
    }
}

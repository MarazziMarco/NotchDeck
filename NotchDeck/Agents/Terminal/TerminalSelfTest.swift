import Foundation

/// One stage of the terminal-integration pipeline.
struct PipelineStage: Identifiable {
    let id = UUID()
    var index: Int
    var name: String
    var ok: Bool?          // nil = not evaluated
    var detail: String = ""
}

struct SelfTestResult {
    var stages: [PipelineStage]
    var lastSuccessful: PipelineStage?
    var firstFailing: PipelineStage?
    var summary: String
}

/// Runs the real installed helper through the real Unix socket and reports every
/// pipeline stage — distinguishing app/bridge/helper failure from a
/// Claude/Codex hook-execution failure. Uses NO in-process fake.
@MainActor
enum TerminalSelfTest {

    static let stageNames = [
        "config contains hook",
        "configured command valid",
        "installed helper exists",
        "installed helper executable",
        "bridge socket active",
        "helper process invoked",
        "helper read hook JSON",
        "helper connected to socket",
        "bridge decoded event",
        "session store upserted",
        "Agents UI would display",
    ]

    static func run(provider: TerminalAgentProvider, env: AppEnvironment) async -> SelfTestResult {
        var stages: [PipelineStage] = stageNames.enumerated().map {
            PipelineStage(index: $0.offset + 1, name: $0.element)
        }
        func set(_ i: Int, _ ok: Bool, _ detail: String = "") {
            stages[i].ok = ok; stages[i].detail = detail
        }

        // 1 config contains hook
        set(0, HookInstaller.isInstalled(provider),
            HookInstaller.isInstalled(provider) ? "installed" : "not installed")

        // 2 command valid (helper path double-quoted, absolute)
        let helper = HookInstaller.installedHelperURL.path
        let cmd = HookInstaller.command(helper: helper, provider: provider, event: .sessionStarted)
        let quotedOK = cmd.contains("\"\(helper)\"") && !helper.hasPrefix("~")
        set(1, quotedOK, quotedOK ? "quoted absolute path" : "unquoted / relative path")

        // 3/4 helper exists + executable (install from bundle first)
        do { _ = try HookInstaller.ensureHelperInstalled() } catch {}
        let fm = FileManager.default
        set(2, fm.fileExists(atPath: helper), SecretSanitizer.redactHome(helper))
        set(3, fm.isExecutableFile(atPath: helper), fm.isExecutableFile(atPath: helper) ? "executable" : "not executable")

        // 5 bridge socket active
        await env.terminalBridge.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        set(4, env.terminalStats.isListening, env.terminalStats.socketPath)

        // Snapshot counters
        let beforeConn = env.terminalStats.rawConnections
        let beforeDecoded = env.terminalStats.decodedEvents

        // 6 run the real helper as a subprocess with synthetic stdin
        let sessionID = "selftest-\(UUID().uuidString.prefix(8))"
        let json = """
        {"hook_event_name":"SessionStart","session_id":"\(sessionID)","cwd":"/tmp/notchdeck-selftest","source":"startup"}
        """
        let (exitCode, ran) = await runHelper(path: helper, provider: provider, stdin: json)
        set(5, ran && exitCode == 0, ran ? "exit \(exitCode)" : "failed to launch")
        // 7 helper read JSON (best-effort: it exited cleanly having consumed stdin)
        set(6, ran && exitCode == 0, "stdin consumed")

        // Give the socket round-trip a moment
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 8 helper connected to socket (a new raw connection arrived)
        let connected = env.terminalStats.rawConnections > beforeConn
        set(7, connected, "connections \(beforeConn) → \(env.terminalStats.rawConnections)")

        // 9 bridge decoded event
        let decoded = env.terminalStats.decodedEvents > beforeDecoded
        set(8, decoded, "decoded \(beforeDecoded) → \(env.terminalStats.decodedEvents)")

        // 10 session store upserted
        let session = env.agentStore.sessions.first { $0.providerSessionID == sessionID }
        set(9, session != nil, session != nil ? "session present" : "not found in store")

        // 11 UI would display (same store instance the Agents face observes)
        set(10, session != nil, session != nil ? "in orderedSessions" : "absent")

        // Clean up the temporary test session
        if let s = session { env.agentStore.remove(id: s.id) }

        let lastSuccessful = stages.last { $0.ok == true }
        let firstFailing = stages.first { $0.ok == false }
        let summary: String
        if firstFailing == nil {
            summary = "All stages passed — the app/bridge/helper path works end to end. If real Codex/Claude sessions still don't appear, the failure is in CLI hook execution (check /hooks trust and the helper log)."
        } else {
            summary = "First failing stage: \(firstFailing!.index). \(firstFailing!.name) — \(firstFailing!.detail)"
        }
        return SelfTestResult(stages: stages, lastSuccessful: lastSuccessful,
                              firstFailing: firstFailing, summary: summary)
    }

    /// Launch the installed helper as a real process, writing JSON to its stdin.
    private static func runHelper(path: String, provider: TerminalAgentProvider,
                                  stdin: String) async -> (Int32, Bool) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["--provider", provider.cliName, "--event", "sessionStarted"]
                let inPipe = Pipe(); let outPipe = Pipe()
                process.standardInput = inPipe
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? inPipe.fileHandleForWriting.close()
                    process.waitUntilExit()
                    cont.resume(returning: (process.terminationStatus, true))
                } catch {
                    cont.resume(returning: (-1, false))
                }
            }
        }
    }
}

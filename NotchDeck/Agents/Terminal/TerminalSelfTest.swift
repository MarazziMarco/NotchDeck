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

struct TerminalSelfTestSnapshot {
    let provider: TerminalAgentProvider
    let configInstalled: Bool
    let commandValid: Bool
    let helperPath: String
    let helperExists: Bool
    let helperExecutable: Bool
    let bridgeListening: Bool
    let lifecycleError: String?
    let rawConnections: Int
    let decodedEvents: Int
    let connectedSessions: Int
    let storeSessions: Int
    let uiObservedSessions: Int
}

/// Reads the current integration pipeline without repairing or exercising it.
/// In particular this diagnostic never installs a helper, starts the bridge, or
/// injects a synthetic session into the production store.
@MainActor
enum TerminalSelfTest {

    static let stageNames = [
        "config contains hook",
        "configured command valid",
        "installed helper exists",
        "installed helper executable",
        "bridge socket active",
        "bridge lifecycle healthy",
        "helper connection observed",
        "hook event decoded",
        "connected session observed",
        "session store observed",
        "Agents UI observed",
    ]

    static func run(provider: TerminalAgentProvider, env: AppEnvironment) async -> SelfTestResult {
        let helper = HookInstaller.installedHelperURL.path
        let command = HookInstaller.command(
            helper: helper,
            provider: provider,
            event: .sessionStarted
        )
        let commandValid = command.contains("\"\(helper)\"") && !helper.hasPrefix("~")
        let fileManager = FileManager.default
        return evaluate(.init(
            provider: provider,
            configInstalled: HookInstaller.isInstalled(provider),
            commandValid: commandValid,
            helperPath: helper,
            helperExists: fileManager.fileExists(atPath: helper),
            helperExecutable: fileManager.isExecutableFile(atPath: helper),
            bridgeListening: env.terminalStats.isListening,
            lifecycleError: env.terminalStats.lastLifecycleError,
            rawConnections: env.terminalStats.rawConnections,
            decodedEvents: env.terminalStats.decodedEvents,
            connectedSessions: env.terminalStats.connectedCount,
            storeSessions: env.terminalStats.storeCount,
            uiObservedSessions: env.terminalStats.uiObservedCount
        ))
    }

    static func evaluate(_ snapshot: TerminalSelfTestSnapshot) -> SelfTestResult {
        var stages: [PipelineStage] = stageNames.enumerated().map {
            PipelineStage(index: $0.offset + 1, name: $0.element)
        }
        func set(_ i: Int, _ ok: Bool, _ detail: String = "") {
            stages[i].ok = ok; stages[i].detail = detail
        }

        set(0, snapshot.configInstalled,
            snapshot.configInstalled ? "installed" : "not installed")
        set(1, snapshot.commandValid,
            snapshot.commandValid ? "quoted absolute path" : "unquoted / relative path")
        set(2, snapshot.helperExists, SecretSanitizer.redactHome(snapshot.helperPath))
        set(3, snapshot.helperExecutable,
            snapshot.helperExecutable ? "executable" : "not executable")
        set(4, snapshot.bridgeListening,
            snapshot.bridgeListening ? "listener active" : "not listening")
        set(5, snapshot.lifecycleError == nil, snapshot.lifecycleError ?? "no lifecycle error")
        set(6, snapshot.rawConnections > 0, "\(snapshot.rawConnections) connection(s)")
        set(7, snapshot.decodedEvents > 0, "\(snapshot.decodedEvents) decoded event(s)")
        set(8, snapshot.connectedSessions > 0,
            "\(snapshot.connectedSessions) connected session(s)")
        set(9, snapshot.storeSessions > 0, "\(snapshot.storeSessions) stored session(s)")
        set(10, snapshot.uiObservedSessions > 0,
            "\(snapshot.uiObservedSessions) session(s) observed by UI")

        let lastSuccessful = stages.last { $0.ok == true }
        let firstFailing = stages.first { $0.ok == false }
        let summary: String
        if firstFailing == nil {
            summary = "All currently observed stages are healthy."
        } else {
            summary = "First failing stage: \(firstFailing!.index). \(firstFailing!.name) — \(firstFailing!.detail)"
        }
        return SelfTestResult(stages: stages, lastSuccessful: lastSuccessful,
                              firstFailing: firstFailing, summary: summary)
    }
}

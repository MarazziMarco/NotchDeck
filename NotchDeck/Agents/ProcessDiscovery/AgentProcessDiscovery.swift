import Foundation
import Darwin

/// A PID is not a durable process identity because the kernel reuses it. The
/// BSD start timestamp makes an identity exact across scans and relaunches.
struct AgentProcessIdentity: Hashable, Codable, Sendable {
    let pid: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

enum AgentProviderClassification: String, Codable, Equatable, Sendable {
    case nativeClaude
    case nodeClaude
    case nativeCodex
    case wrappedClaude
    case wrappedCodex

    var provider: AgentProviderKind {
        switch self {
        case .nativeClaude, .nodeClaude, .wrappedClaude: return .claudeCode
        case .nativeCodex, .wrappedCodex: return .codex
        }
    }

    var isWrapper: Bool {
        self == .wrappedClaude || self == .wrappedCodex
    }
}

/// Structural provider classification. Raw argv is used transiently and is
/// never stored in a session or diagnostic record.
enum AgentProviderClassifier {
    private static let directExecutables: Set<String> = [
        "claude", "claude.exe", "codex", "node", "nodejs",
    ]
    /// Structural launchers whose command position can be parsed without
    /// treating prompts, environment values, or shell command strings as
    /// provider evidence.
    private static let supportedLaunchers: Set<String> = ["env", "mise", "volta"]

    static func shouldInspectArguments(executableBasename: String) -> Bool {
        let basename = executableBasename.lowercased()
        return directExecutables.contains(basename) || supportedLaunchers.contains(basename)
    }

    static func classify(executablePath: String, arguments: [String]) -> AgentProviderClassification? {
        let executable = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
        let normalizedExecutablePath = executablePath
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        guard executable != "notchdeck-agent-hook" else { return nil }
        let argvExecutable = arguments.first.map {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
        }

        if ["claude", "claude.exe"].contains(executable),
           let argvExecutable,
           ["claude", "claude.exe"].contains(argvExecutable) {
            guard !normalizedExecutablePath.contains(".app/contents/macos/") else { return nil }
            return .nativeClaude
        }
        if executable == "codex", argvExecutable == "codex" {
            guard !isCodexAdministrativeProcess(arguments) else { return nil }
            return .nativeCodex
        }

        if executable == "node" || executable == "nodejs" {
            guard let script = nodeScriptArgument(arguments) else { return nil }
            let normalized = script.replacingOccurrences(of: "\\", with: "/").lowercased()
            guard normalized.hasSuffix("/cli.js"),
                  normalized.contains("/@anthropic-ai/claude-code/") else { return nil }
            return .nodeClaude
        }

        guard supportedLaunchers.contains(executable),
              argvExecutable == executable,
              let commandIndex = wrappedCommandIndex(
                  launcher: executable,
                  arguments: arguments
              ) else { return nil }
        let providerArguments = Array(arguments[commandIndex...])
        let command = URL(fileURLWithPath: providerArguments[0]).lastPathComponent.lowercased()
        if command == "claude" || command == "claude.exe" {
            return .wrappedClaude
        }
        if command == "codex", !isCodexAdministrativeProcess(providerArguments) {
            return .wrappedCodex
        }
        return nil
    }

    private static func wrappedCommandIndex(
        launcher: String,
        arguments: [String]
    ) -> Int? {
        guard arguments.count > 1 else { return nil }
        switch launcher {
        case "env":
            let optionsWithValue: Set<String> = ["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--" {
                    return arguments.indices.contains(index + 1) ? index + 1 : nil
                }
                if optionsWithValue.contains(argument) {
                    index += 2
                    continue
                }
                if argument.hasPrefix("-") || isEnvironmentAssignment(argument) {
                    index += 1
                    continue
                }
                return index
            }
            return nil
        case "mise":
            guard ["exec", "x"].contains(arguments[1]),
                  let separator = arguments.firstIndex(of: "--"),
                  arguments.indices.contains(separator + 1) else { return nil }
            return separator + 1
        case "volta":
            guard arguments[1] == "run",
                  let separator = arguments.firstIndex(of: "--"),
                  arguments.indices.contains(separator + 1) else { return nil }
            return separator + 1
        default:
            return nil
        }
    }

    private static func isEnvironmentAssignment(_ argument: String) -> Bool {
        guard let equals = argument.firstIndex(of: "="), equals != argument.startIndex else {
            return false
        }
        let name = argument[..<equals]
        guard let first = name.first,
              first == "_" || first.isLetter else { return false }
        return name.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    /// Long-lived Codex infrastructure processes share the `codex` executable
    /// but are not interactive agent sessions. Keep this exclusion narrow so
    /// real exec/resume/fork/review processes remain visible.
    private static func isCodexAdministrativeProcess(_ arguments: [String]) -> Bool {
        let optionsWithValue: Set<String> = [
            "-c", "--config", "--enable", "--disable", "-m", "--model",
            "-s", "--sandbox", "-a", "--ask-for-approval", "-C", "--cd",
            "--add-dir", "-p", "--profile",
        ]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { return false }
            if optionsWithValue.contains(argument) {
                index += 2
                continue
            }
            if argument.hasPrefix("-") {
                index += 1
                continue
            }
            return [
                "app-server",
                "mcp-server",
                "remote-control",
                "completion",
                "login",
                "logout",
            ].contains(argument.lowercased())
        }
        return false
    }

    /// Finds Node's script position without treating prompt/tool arguments as
    /// executable evidence.
    private static func nodeScriptArgument(_ arguments: [String]) -> String? {
        guard !arguments.isEmpty else { return nil }
        var index = 1
        let optionsWithValue: Set<String> = [
            "-e", "--eval", "-p", "--print", "-r", "--require",
            "--loader", "--import", "--conditions",
        ]
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                return arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            }
            if optionsWithValue.contains(argument) {
                index += 2
                continue
            }
            if argument.hasPrefix("-") {
                index += 1
                continue
            }
            return argument
        }
        return nil
    }
}

enum AgentTTYSource: String, Codable, Equatable, Sendable {
    case process
    case ancestor
    case hook
}

struct AgentTTYCapture: Hashable, Codable, Sendable {
    let device: UInt32?
    let canonicalPath: String
    let source: AgentTTYSource
    let capturedAt: Date
    let sourceIdentity: AgentProcessIdentity?

    init(device: UInt32?, canonicalPath: String, source: AgentTTYSource,
         capturedAt: Date, sourceIdentity: AgentProcessIdentity?) {
        self.device = device
        self.canonicalPath = TerminalTabMatching.canonical(canonicalPath)
        self.source = source
        self.capturedAt = capturedAt
        self.sourceIdentity = sourceIdentity
    }
}

enum AgentProcessPresence: String, Codable, Equatable, Sendable {
    case running
    case ended
}

struct AgentProcessSnapshot: Equatable, Sendable {
    let identity: AgentProcessIdentity
    let parentPID: Int32
    let provider: AgentProviderKind
    let classification: AgentProviderClassification
    let executableBasename: String
    let workingDirectory: String?
    let controllingTTY: AgentTTYCapture?
    let discoveredAt: Date
}

protocol AgentProcessDiscovering: Sendable {
    func discover(at timestamp: Date) -> [AgentProcessSnapshot]
}

struct AgentProcessRecord: Equatable, Sendable {
    let identity: AgentProcessIdentity
    let parentPID: Int32
}

enum ProcessAncestryResolver {
    static func resolve(
        from pid: Int32,
        maxDepth: Int = 16,
        record: (Int32) -> AgentProcessRecord?
    ) -> [AgentProcessIdentity] {
        guard pid > 1, maxDepth > 0 else { return [] }
        var result: [AgentProcessIdentity] = []
        var visited = Set<Int32>()
        var current = pid
        for _ in 0..<maxDepth {
            guard current > 1, visited.insert(current).inserted,
                  let item = record(current) else { break }
            result.append(item.identity)
            current = item.parentPID
        }
        return result
    }
}

enum AgentHookCorrelationConfidence: String, Codable, Equatable {
    case exactAncestry
    case uniqueProviderDirectory
}

struct AgentHookProcessMatch: Equatable {
    let sessionID: UUID
    let confidence: AgentHookCorrelationConfidence
}

enum AgentHookProcessCorrelator {
    static func match(
        provider: AgentProviderKind,
        ancestorIdentities: [AgentProcessIdentity],
        cwd: String?,
        discoveredAt: Date,
        sessions: [AgentSession]
    ) -> AgentHookProcessMatch? {
        let identities = Set(ancestorIdentities)
        let exact = sessions.filter {
            $0.provider == provider
                && $0.processIdentity.map(identities.contains) == true
        }
        if exact.count == 1 {
            return AgentHookProcessMatch(sessionID: exact[0].id, confidence: .exactAncestry)
        }
        guard exact.isEmpty, let cwd else { return nil }
        let candidates = sessions.filter {
            $0.provider == provider
                && $0.processPresence == .running
                && $0.projectPath == cwd
                && abs(discoveredAt.timeIntervalSince($0.processLastSeenAt ?? .distantPast)) <= 10
        }
        guard candidates.count == 1 else { return nil }
        return AgentHookProcessMatch(
            sessionID: candidates[0].id,
            confidence: .uniqueProviderDirectory
        )
    }
}

/// Prefer the real provider process over an allowlisted launcher that remains
/// alive as its ancestor. A wrapper-only process is retained, while a native or
/// Node provider descendant prevents a duplicate card.
enum AgentProcessSnapshotNormalizer {
    static func preferProviderProcesses(
        _ snapshots: [AgentProcessSnapshot],
        record: (Int32) -> AgentProcessRecord?
    ) -> [AgentProcessSnapshot] {
        snapshots.filter { candidate in
            guard candidate.classification.isWrapper else { return true }
            return !snapshots.contains { process in
                guard !process.classification.isWrapper,
                      process.provider == candidate.provider,
                      process.identity != candidate.identity else { return false }
                let ancestry = ProcessAncestryResolver.resolve(
                    from: process.parentPID,
                    maxDepth: 16,
                    record: record
                )
                return ancestry.contains(candidate.identity)
            }
        }
    }
}

enum AgentProcessReconciler {
    static func reconcile(
        existing: [AgentSession],
        snapshots: [AgentProcessSnapshot],
        now: Date,
        managedProcessIDs: [UUID: Int32] = [:],
        makeID: (AgentProcessIdentity) -> UUID = { _ in UUID() }
    ) -> [AgentSession] {
        var result = existing
        let live = Set(snapshots.map(\.identity))

        for index in result.indices where result[index].processPresence == .running {
            guard let identity = result[index].processIdentity, !live.contains(identity) else { continue }
            let pidWasReused = snapshots.contains {
                $0.identity.pid == identity.pid && $0.identity != identity
            }
            let misses = (result[index].processMissCount ?? 0) + 1
            result[index].processMissCount = misses
            guard pidWasReused || misses >= 2 else { continue }
            result[index].processPresence = .ended
            result[index].processEndedAt = now
            result[index].lastActivityAt = now
            if result[index].status == .running || result[index].status == .starting {
                result[index].status = .completed
            }
        }

        for snapshot in snapshots {
            if let index = result.firstIndex(where: { $0.processIdentity == snapshot.identity }) {
                apply(snapshot, to: &result[index])
                continue
            }

            // ManagedProcess is the exact process object launched for a session.
            // Its live PID selects the matching kernel snapshot; applying that
            // snapshot adds the start timestamp, so PID reuse never becomes the
            // persisted identity. This also keeps same-directory launches
            // distinct without guessing from cwd or timing.
            let exactManagedCandidates = result.indices.filter {
                result[$0].processIdentity == nil
                    && result[$0].isManaged
                    && result[$0].provider == snapshot.provider
                    && managedProcessIDs[result[$0].id] == snapshot.identity.pid
            }
            if exactManagedCandidates.count == 1 {
                apply(snapshot, to: &result[exactManagedCandidates[0]])
                continue
            }

            // Managed sessions are created immediately, before their subprocess
            // publishes a PID. Attach the first scan only when provider, exact
            // cwd, active lifecycle, and process start time are all consistent
            // and the match is unique on both sides.
            let managedCandidates = result.indices.filter {
                managedProcessIDs[result[$0].id] == nil
                    && isManagedCandidate(result[$0], for: snapshot)
            }
            if managedCandidates.count == 1 {
                let candidate = result[managedCandidates[0]]
                let matchingSnapshots = snapshots.filter {
                    isManagedCandidate(candidate, for: $0)
                }
                if matchingSnapshots.count == 1 {
                    apply(snapshot, to: &result[managedCandidates[0]])
                    continue
                }
            }

            // A hook-only compatibility card may already have enough exact
            // metadata to merge. Never use cwd alone when more than one process
            // could match.
            let candidates = result.indices.filter {
                result[$0].processIdentity == nil
                    && result[$0].provider == snapshot.provider
                    && result[$0].isBridgeConnected
                    && result[$0].pid == snapshot.identity.pid
            }
            if candidates.count == 1 {
                apply(snapshot, to: &result[candidates[0]])
                continue
            }

            // Hooks commonly arrive before the first process scan and their
            // helper PID is intentionally not treated as the agent PID. Merge
            // by provider + exact cwd + temporal proximity only when both
            // sides are unique. Two same-directory agents must stay distinct.
            let matchingSnapshots = snapshots.filter {
                $0.provider == snapshot.provider
                    && $0.workingDirectory == snapshot.workingDirectory
            }
            let hookCandidates = result.indices.filter {
                result[$0].processIdentity == nil
                    && result[$0].provider == snapshot.provider
                    && result[$0].isBridgeConnected
                    && !result[$0].projectPath.isEmpty
                    && result[$0].projectPath == snapshot.workingDirectory
                    && abs(snapshot.discoveredAt.timeIntervalSince(result[$0].lastActivityAt)) <= 10
            }
            if matchingSnapshots.count == 1, hookCandidates.count == 1 {
                apply(snapshot, to: &result[hookCandidates[0]])
                continue
            }

            var session = AgentSession(
                id: makeID(snapshot.identity),
                provider: snapshot.provider,
                title: snapshot.workingDirectory.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                } ?? "\(snapshot.provider.displayName) \(snapshot.identity.pid)",
                projectPath: snapshot.workingDirectory ?? "",
                status: .running,
                lastActivityAt: snapshot.discoveredAt,
                isManaged: false,
                startedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(snapshot.identity.startSeconds)
                        + TimeInterval(snapshot.identity.startMicroseconds) / 1_000_000
                ),
                terminalTTY: snapshot.controllingTTY?.canonicalPath,
                terminalAppName: nil,
                pid: snapshot.identity.pid,
                ppid: snapshot.parentPID
            )
            session.processIdentity = snapshot.identity
            session.processPresence = .running
            session.processLastSeenAt = snapshot.discoveredAt
            session.ttyCapture = snapshot.controllingTTY
            result.append(session)
        }
        return result
    }

    private static func isManagedCandidate(
        _ session: AgentSession,
        for snapshot: AgentProcessSnapshot
    ) -> Bool {
        guard session.processIdentity == nil,
              session.isManaged,
              session.provider == snapshot.provider,
              !session.projectPath.isEmpty,
              session.projectPath == snapshot.workingDirectory,
              [.starting, .running, .waitingForInput, .waitingForApproval]
                .contains(session.status) else { return false }
        let processStart = Date(
            timeIntervalSince1970:
                TimeInterval(snapshot.identity.startSeconds)
                + TimeInterval(snapshot.identity.startMicroseconds) / 1_000_000
        )
        return abs(processStart.timeIntervalSince(session.startedAt)) <= 10
    }

    private static func apply(_ snapshot: AgentProcessSnapshot, to session: inout AgentSession) {
        session.processIdentity = snapshot.identity
        session.processPresence = .running
        session.processLastSeenAt = snapshot.discoveredAt
        session.processEndedAt = nil
        session.processMissCount = 0
        session.pid = snapshot.identity.pid
        session.ppid = snapshot.parentPID
        if let directory = snapshot.workingDirectory, !directory.isEmpty {
            session.projectPath = directory
            if session.title.isEmpty || session.title.hasPrefix(session.provider.displayName) {
                session.title = URL(fileURLWithPath: directory).lastPathComponent
            }
        }
        if let tty = snapshot.controllingTTY {
            session.ttyCapture = tty
            session.terminalTTY = tty.canonicalPath
        }
        if session.status == .completed || session.status == .interrupted || session.status == .unavailable {
            session.status = .running
        }
    }
}

import Foundation

/// Versioned JSONL protocol spoken over the local Unix-domain socket between the
/// `notchdeck-agent-hook` helper and NotchDeck's `TerminalAgentBridge`.
/// Foundation-only so it can be shared by both the app and the CLI helper target.
public enum TerminalAgentProtocol {
    /// Bump when the wire format changes incompatibly.
    public static let version = 1

    /// Socket path under the user's Application Support. User-only directory.
    public static func socketURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NotchDeck", isDirectory: true)
            .appendingPathComponent("terminal-bridge.sock")
    }
}

/// The three approval timeouts. INVARIANT (validated by test):
///   UI fallback  <  helper hard deadline  <  Claude hook timeout
/// so the outer Claude hook always outlives the helper, and the helper always
/// outlives the UI decision window.
public enum HookTimeouts {
    public static let uiFallbackSeconds: TimeInterval = 8
    public static let helperHardDeadlineSeconds: TimeInterval = 15
    public static let claudeHookTimeoutSeconds: Int = 30

    public static var isValidHierarchy: Bool {
        uiFallbackSeconds < helperHardDeadlineSeconds
            && helperHardDeadlineSeconds < TimeInterval(claudeHookTimeoutSeconds)
    }
}

public enum TerminalAgentEventType: String, Codable {
    case sessionStarted
    case sessionResumed
    case userPromptSubmitted
    case toolStarted
    case permissionRequested
    case toolCompleted
    case agentStopped
    case sessionEnded
    case heartbeat
    /// Helper → app acknowledgement that a decision was emitted to the CLI's
    /// stdout (so the app shows "Approved" only after real delivery).
    case decisionDelivered
}

public enum TerminalAgentProvider: String, Codable {
    case codex
    case claudeCode
    case unknown

    /// Short CLI name used on the helper command line (`--provider claude`).
    public var cliName: String {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .unknown: return "unknown"
        }
    }

    /// Parse either the raw value or the CLI name / common aliases.
    public static func parse(_ s: String) -> TerminalAgentProvider {
        switch s.lowercased() {
        case "codex": return .codex
        case "claude", "claudecode", "claude-code", "claude_code": return .claudeCode
        default: return .unknown
        }
    }
}

/// One event sent helper → app. Only strictly necessary metadata is carried;
/// never full prompt text, tokens or sensitive environment.
public struct TerminalAgentEvent: Codable, Equatable {
    public var protocolVersion: Int
    public var type: TerminalAgentEventType
    public var provider: TerminalAgentProvider
    public var sessionID: String
    public var cwd: String?
    public var timestamp: Double
    // Optional context
    public var turnID: String?
    public var toolName: String?
    /// Short, sanitized command/description for display — never the full prompt.
    public var summary: String?
    public var permissionMode: String?
    public var pid: Int32?
    public var ppid: Int32?
    public var tty: String?
    public var terminalApp: String?
    /// Correlates a permission request with its decision response.
    public var requestID: String?
    /// Optional tool-use identity for precise approval correlation.
    public var toolUseID: String?
    /// Provider hook field (e.g. Stop's last_assistant_message) when available.
    public var lastAssistantMessage: String?
    /// Provider transcript path — used only as a fallback, schema-version-dependent.
    public var transcriptPath: String?
    /// Terminal identity for exact focus / lifecycle.
    public var terminalBundleID: String?
    public var termSessionID: String?
    public var shellPID: Int32?

    public init(type: TerminalAgentEventType,
                provider: TerminalAgentProvider,
                sessionID: String,
                cwd: String? = nil,
                timestamp: Double,
                turnID: String? = nil,
                toolName: String? = nil,
                summary: String? = nil,
                permissionMode: String? = nil,
                pid: Int32? = nil,
                ppid: Int32? = nil,
                tty: String? = nil,
                terminalApp: String? = nil,
                requestID: String? = nil,
                toolUseID: String? = nil,
                lastAssistantMessage: String? = nil,
                transcriptPath: String? = nil,
                terminalBundleID: String? = nil,
                termSessionID: String? = nil,
                shellPID: Int32? = nil) {
        self.protocolVersion = TerminalAgentProtocol.version
        self.type = type
        self.provider = provider
        self.sessionID = sessionID
        self.cwd = cwd
        self.timestamp = timestamp
        self.turnID = turnID
        self.toolName = toolName
        self.summary = summary
        self.permissionMode = permissionMode
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.terminalApp = terminalApp
        self.requestID = requestID
        self.toolUseID = toolUseID
        self.lastAssistantMessage = lastAssistantMessage
        self.transcriptPath = transcriptPath
        self.terminalBundleID = terminalBundleID
        self.termSessionID = termSessionID
        self.shellPID = shellPID
    }
}

/// Decision sent app → helper for a permission request.
public struct TerminalAgentDecision: Codable, Equatable {
    public enum Behavior: String, Codable { case allow, deny }
    public var protocolVersion: Int
    public var requestID: String
    public var behavior: Behavior
    public var message: String?
    /// When true this is a RELEASE, not a decision: the helper should stop
    /// waiting and return empty stdout so the CLI shows its native prompt. Sent
    /// by the app at the hybrid fallback deadline so the helper exits promptly
    /// instead of blocking to its hard deadline.
    public var fallback: Bool

    public init(requestID: String, behavior: Behavior, message: String? = nil, fallback: Bool = false) {
        self.protocolVersion = TerminalAgentProtocol.version
        self.requestID = requestID
        self.behavior = behavior
        self.message = message
        self.fallback = fallback
    }
}

/// The EXACT provider stdout contract a PermissionRequest hook must emit.
///
/// Audited against the installed CLIs (Claude Code 2.1.x, Codex 0.14x): the
/// `PermissionRequest` hook is answered by
///   {"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow"|"deny"[,"permissionDecisionReason":"…"]}}
/// The `hookEventName` MUST equal the firing hook event, `permissionDecision`
/// MUST be one of allow/deny/ask/defer (a plain string — NOT the PreToolUse
/// `decision:{behavior}` / SDK `{behavior,updatedInput}` shape). An unrecognised
/// shape is rejected by the CLI ("Unknown hook permissionDecision type") and it
/// falls back to its own native prompt — the double-confirmation bug.
///
/// stdout must contain ONLY this line; all diagnostics go to stderr / the log.
public enum PermissionResponse {
    /// The hook event name both providers register the synchronous helper under.
    public static let hookEventName = "PermissionRequest"

    /// Provider-valid decision JSON (no trailing newline). Deterministic key
    /// order via sorted keys so it is exactly assertable in tests.
    public static func json(provider: TerminalAgentProvider,
                            behavior: TerminalAgentDecision.Behavior,
                            message: String?) -> String {
        let decision = behavior == .allow ? "allow" : "deny"
        let obj: [String: Any]
        switch provider {
        case .claudeCode, .codex:
            var inner: [String: Any] = ["hookEventName": hookEventName,
                                        "permissionDecision": decision]
            if behavior == .deny {
                inner["permissionDecisionReason"] = message ?? "Denied in NotchDeck"
            }
            obj = ["hookSpecificOutput": inner]
        case .unknown:
            obj = ["permissionDecision": decision]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    /// The exact bytes the helper writes to stdout: the JSON line + one newline.
    public static func stdoutLine(provider: TerminalAgentProvider,
                                  behavior: TerminalAgentDecision.Behavior,
                                  message: String?) -> String {
        json(provider: provider, behavior: behavior, message: message) + "\n"
    }
}

/// JSONL codec shared by both sides.
public enum TerminalAgentCodec {
    public static func encodeLine<T: Encodable>(_ value: T) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decodeEvent(_ line: String) -> TerminalAgentEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TerminalAgentEvent.self, from: data)
    }

    public static func decodeDecision(_ line: String) -> TerminalAgentDecision? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TerminalAgentDecision.self, from: data)
    }
}

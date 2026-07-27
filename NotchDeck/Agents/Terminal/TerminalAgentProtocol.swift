import Foundation

/// Versioned JSONL protocol spoken over the local Unix-domain socket between the
/// `notchdeck-agent-hook` helper and NotchDeck's `TerminalAgentBridge`.
/// Foundation-only so it can be shared by both the app and the CLI helper target.
public enum TerminalAgentProtocol {
    /// Bump when the wire format changes incompatibly.
    public static let version = 2

    /// Socket path under the user's Application Support. User-only directory.
    public static func socketURL() -> URL {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHDECK_AGENT_HOOK_TESTING"] == "1",
           let path = ProcessInfo.processInfo.environment["NOTCHDECK_TEST_SOCKET_PATH"],
           path.hasPrefix(FileManager.default.temporaryDirectory.path + "/") {
            return URL(fileURLWithPath: path)
        }
        #endif
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
    public static let maximumUIFallbackSeconds: TimeInterval = 15
    public static let notchOnlyDecisionSeconds: TimeInterval = 20
    public static let helperHardDeadlineSeconds: TimeInterval = 25
    public static let claudeHookTimeoutSeconds: Int = 30

    public static var isValidHierarchy: Bool {
        maximumUIFallbackSeconds < notchOnlyDecisionSeconds
            && notchOnlyDecisionSeconds < helperHardDeadlineSeconds
            && helperHardDeadlineSeconds < TimeInterval(claudeHookTimeoutSeconds)
    }
}

public enum TerminalAgentEventType: String, Codable {
    case sessionStarted
    case sessionResumed
    case userPromptSubmitted
    case toolStarted
    /// Legacy PreToolUse decision event retained for compatibility with v3
    /// helpers. New installs treat it as activity and release it safely.
    case toolPermissionRequested
    /// Authoritative human-in-the-loop hook. The helper blocks on this exact
    /// connection until NotchDeck answers or releases it to the native prompt.
    case permissionRequested
    case toolCompleted
    case agentStopped
    case sessionEnded
    case heartbeat
    /// Helper → app: the provider response was written to stdout and flushed.
    /// This proves the bytes were emitted — NOT that the provider parsed/accepted
    /// them. The UI shows "Sent to Claude", never "Approved", on this signal.
    case responseWritten
    /// Helper closed provider-facing stdout and is about to close its bridge
    /// socket. Still not proof that the provider accepted the response.
    case helperExited
    /// Deprecated alias of `responseWritten` (older helper builds).
    case decisionDelivered
}

public enum TerminalAgentProvider: String, Codable, Sendable {
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
    /// Unique per helper invocation. Provider-native request IDs are not
    /// globally unique across sessions and therefore never own a socket.
    public var transactionID: String?
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
                transactionID: String? = nil,
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
        self.transactionID = transactionID
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
    /// Provider-native request identity retained for correlation.
    public var requestID: String
    /// Exact helper invocation that owns the live socket.
    public var transactionID: String
    public var behavior: Behavior
    public var message: String?
    /// When true this is a RELEASE, not a decision: the helper should stop
    /// waiting and return empty stdout so the CLI shows its native prompt. Sent
    /// by the app at the hybrid fallback deadline so the helper exits promptly
    /// instead of blocking to its hard deadline.
    public var fallback: Bool

    public init(requestID: String, transactionID: String? = nil,
                behavior: Behavior, message: String? = nil, fallback: Bool = false) {
        self.protocolVersion = TerminalAgentProtocol.version
        self.requestID = requestID
        self.transactionID = transactionID ?? requestID
        self.behavior = behavior
        self.message = message
        self.fallback = fallback
    }
}

public struct AgentPermissionRequest: Equatable {
    public let provider: TerminalAgentProvider
    public let sessionID: String
    public let turnID: String?
    public let toolName: String?
    public let cwd: String?
    public let requestID: String
}

public enum AgentPermissionAdapterError: Error, Equatable {
    case wrongEvent
    case missingSessionID
    case missingTurnID
}

/// Each CLI owns its payload parsing, correlation key, response encoding, and
/// empty-output fallback. The shared UI never guesses a provider schema.
public protocol AgentPermissionProvider {
    var provider: TerminalAgentProvider { get }
    func parse(_ payload: [String: Any]) throws -> AgentPermissionRequest
    func response(behavior: TerminalAgentDecision.Behavior, message: String?) -> Data
    func fallbackResponse() -> Data
}

private enum PermissionPayload {
    static func string(_ payload: [String: Any], _ key: String) -> String? {
        guard let value = payload[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    static func canonicalHash(_ value: Any?) -> String {
        guard let value,
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .fragmentsAllowed]
              )
        else { return "0" }
        // Stable FNV-1a is sufficient for an internal correlation key. Raw input
        // is never persisted or logged.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func line(_ object: [String: Any]) -> Data {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data()
        }
        data.append(0x0A)
        return data
    }
}

public struct ClaudePermissionAdapter: AgentPermissionProvider {
    public let provider: TerminalAgentProvider = .claudeCode
    public init() {}

    public func parse(_ payload: [String: Any]) throws -> AgentPermissionRequest {
        guard PermissionPayload.string(payload, "hook_event_name") == "PermissionRequest" else {
            throw AgentPermissionAdapterError.wrongEvent
        }
        guard let session = PermissionPayload.string(payload, "session_id") else {
            throw AgentPermissionAdapterError.missingSessionID
        }
        let tool = PermissionPayload.string(payload, "tool_name")
        let native = PermissionPayload.string(payload, "request_id")
        let hash = PermissionPayload.canonicalHash(payload["tool_input"])
        let requestID = native ?? [session, tool ?? "tool", hash].joined(separator: "|")
        return AgentPermissionRequest(
            provider: provider,
            sessionID: session,
            turnID: PermissionPayload.string(payload, "turn_id"),
            toolName: tool,
            cwd: PermissionPayload.string(payload, "cwd"),
            requestID: requestID
        )
    }

    public func response(
        behavior: TerminalAgentDecision.Behavior,
        message: String?
    ) -> Data {
        var decision: [String: Any] = ["behavior": behavior.rawValue]
        if behavior == .deny {
            decision["interrupt"] = false
            decision["message"] = message ?? "Denied in NotchDeck"
        }
        return PermissionPayload.line([
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ])
    }

    public func fallbackResponse() -> Data { Data() }
}

public struct CodexPermissionAdapter: AgentPermissionProvider {
    public let provider: TerminalAgentProvider = .codex
    public init() {}

    public func parse(_ payload: [String: Any]) throws -> AgentPermissionRequest {
        guard PermissionPayload.string(payload, "hook_event_name") == "PermissionRequest" else {
            throw AgentPermissionAdapterError.wrongEvent
        }
        guard let session = PermissionPayload.string(payload, "session_id") else {
            throw AgentPermissionAdapterError.missingSessionID
        }
        guard let turn = PermissionPayload.string(payload, "turn_id") else {
            throw AgentPermissionAdapterError.missingTurnID
        }
        let tool = PermissionPayload.string(payload, "tool_name")
        let hash = PermissionPayload.canonicalHash(payload["tool_input"])
        let requestID = [session, turn, tool ?? "tool", hash].joined(separator: "|")
        return AgentPermissionRequest(
            provider: provider,
            sessionID: session,
            turnID: turn,
            toolName: tool,
            cwd: PermissionPayload.string(payload, "cwd"),
            requestID: requestID
        )
    }

    public func response(
        behavior: TerminalAgentDecision.Behavior,
        message: String?
    ) -> Data {
        var decision: [String: Any] = ["behavior": behavior.rawValue]
        if behavior == .deny {
            decision["message"] = message ?? "Denied in NotchDeck"
        }
        return PermissionPayload.line([
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ])
    }

    public func fallbackResponse() -> Data { Data() }
}

public enum AgentPermissionProviders {
    public static func adapter(for provider: TerminalAgentProvider) -> (any AgentPermissionProvider)? {
        switch provider {
        case .claudeCode: return ClaudePermissionAdapter()
        case .codex: return CodexPermissionAdapter()
        case .unknown: return nil
        }
    }
}

/// Compatibility entry point retained for existing callers while all encoding
/// is delegated to the provider-specific adapter.
public enum PermissionResponse {
    public static let decisionHookEvent = "PermissionRequest"

    public static func json(
        provider: TerminalAgentProvider,
        behavior: TerminalAgentDecision.Behavior,
        message: String?,
        hookEvent: String = decisionHookEvent
    ) -> String {
        guard hookEvent == decisionHookEvent,
              let adapter = AgentPermissionProviders.adapter(for: provider) else { return "" }
        return String(decoding: adapter.response(behavior: behavior, message: message).dropLast(), as: UTF8.self)
    }

    public static func stdoutLine(
        provider: TerminalAgentProvider,
        behavior: TerminalAgentDecision.Behavior,
        message: String?,
        hookEvent: String = decisionHookEvent
    ) -> String {
        guard hookEvent == decisionHookEvent,
              let adapter = AgentPermissionProviders.adapter(for: provider) else { return "" }
        return String(decoding: adapter.response(behavior: behavior, message: message), as: UTF8.self)
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

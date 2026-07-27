import Foundation

// MARK: - Connection liveness

/// Live connectivity of a session, independent of its agent status.
enum AgentConnectionState: String, Codable, Equatable {
    case connected
    case stale
    case disconnected
}

/// Pure liveness classifier. Never relies on SessionEnd alone.
enum AgentLiveness {
    /// No heartbeat for this long (but process alive) → stale.
    static let staleGrace: TimeInterval = 20
    /// Hard cutoff with no process info → disconnected.
    static let hardTimeout: TimeInterval = 45

    /// - processAlive: nil when unknown (no PID), true/false when checked.
    static func classify(lastActivity: Date, isBridgeConnected: Bool,
                         isManaged: Bool, hasExternalWindow: Bool,
                         processAlive: Bool?, now: Date) -> AgentConnectionState {
        if processAlive == false { return .disconnected }
        let idle = now.timeIntervalSince(lastActivity)
        if isBridgeConnected {
            if idle <= staleGrace { return .connected }
            if processAlive == true { return .stale }
            return idle <= hardTimeout ? .stale : .disconnected
        }
        if isManaged { return .connected }
        // Plain external: present only while its window/process exists.
        return hasExternalWindow ? .connected : .disconnected
    }
}

/// Process existence probe (kill(pid,0)). Does not signal the process.
enum ProcessLiveness {
    static func isAlive(pid: Int32) -> Bool {
        if pid <= 0 { return false }
        let r = kill(pid, 0)
        return r == 0 || errno == EPERM
    }
}

// MARK: - Terminal presence (lifecycle) vs activity

/// Does the session's ORIGINAL terminal tab/window still exist? This — not
/// approval or hook activity — decides Active vs Recent.
enum AgentTerminalPresence: String, Codable, Equatable {
    case present    // the terminal tab/session is still open
    case missing    // the tab/window/app is gone
    case unknown    // not yet probed / no TTY to match

    /// - terminalAppRunning: is the hosting terminal app still running.
    /// - ttyKnown: do we have a stored TTY to match against.
    /// - ttyActive: nil when not probed; true/false from a tab enumeration.
    static func evaluate(terminalAppRunning: Bool, ttyKnown: Bool, ttyActive: Bool?) -> AgentTerminalPresence {
        if !terminalAppRunning { return .missing }
        guard ttyKnown else { return .unknown }
        switch ttyActive {
        case .some(true): return .present
        case .some(false): return .missing
        case .none: return .unknown
        }
    }
}

/// The agent's activity status, kept SEPARATE from terminal lifecycle. An idle
/// or completed agent whose terminal tab is still open stays in Active.
enum AgentActivityState: String, Codable, Equatable {
    case running
    case waitingForApproval
    case waitingForInput
    case idle
    case completed
    case disconnected

    static func from(_ status: AgentSessionStatus) -> AgentActivityState {
        switch status {
        case .running, .starting: return .running
        case .waitingForApproval: return .waitingForApproval
        case .waitingForInput: return .waitingForInput
        case .idle: return .idle
        case .completed: return .completed
        case .failed, .interrupted, .unavailable: return .disconnected
        }
    }
}

// MARK: - Active / Recent bucketing (terminal-presence driven)

enum AgentBucket: Equatable { case active, recent, hidden }

enum AgentSessionFilter {
    static func bucket(_ session: AgentSession) -> AgentBucket {
        switch session.processPresence {
        case .running: return .active
        case .ended: return .recent
        case .none:
            return bucket(
                presence: session.terminalPresence,
                status: session.status,
                isBridgeConnected: session.isBridgeConnected,
                isManaged: session.isManaged,
                hasExternalWindow: session.externalBundleID != nil
            )
        }
    }

    static func isActiveStatus(_ s: AgentSessionStatus) -> Bool {
        switch s {
        case .starting, .running, .waitingForInput, .waitingForApproval, .idle: return true
        default: return false
        }
    }

    /// Bucket a session by TERMINAL PRESENCE, not by activity/approval. A session
    /// stays Active while its terminal tab exists — even idle, completed, or with
    /// no recent hook events. It moves to Recent only when the terminal is gone.
    static func bucket(presence: AgentTerminalPresence, status: AgentSessionStatus,
                       isBridgeConnected: Bool, isManaged: Bool, hasExternalWindow: Bool) -> AgentBucket {
        switch presence {
        case .missing: return .recent
        case .present: return .active
        case .unknown:
            // Not yet probed: keep connected/managed sessions Active until a probe
            // proves the terminal is gone (never demote on activity alone).
            if isBridgeConnected || isManaged { return .active }
            return hasExternalWindow ? .active : .recent
        }
    }
}

// MARK: - Terminal presence debounce

/// One presence observation for a session on a single enumeration pass.
enum TerminalObservation: Equatable {
    case present         // TTY confirmed open
    case absent          // successful enumeration, TTY not found (a CONFIRMED miss)
    case queryError      // AppleScript/permission/timeout/malformed — NOT a miss
    case appTerminated   // the terminal application is gone
}

/// Debounces terminal presence: a tab must be CONFIRMED absent three consecutive
/// enumerations before the session is marked missing. Errors never count and
/// reset nothing; any confirmed detection resets the miss counter to zero;
/// terminal termination marks missing immediately.
enum TerminalPresenceDebounce {
    /// Consecutive confirmed misses required to declare the tab gone.
    static let missThreshold = 3

    struct State: Equatable { var presence: AgentTerminalPresence; var missCount: Int }

    static func step(_ prev: State, _ obs: TerminalObservation) -> State {
        switch obs {
        case .present:
            return State(presence: .present, missCount: 0)              // reset
        case .queryError:
            // Stay Active; presence unknown; counter unchanged (not a miss).
            return State(presence: .unknown, missCount: prev.missCount)
        case .appTerminated:
            return State(presence: .missing, missCount: missThreshold)  // immediate
        case .absent:
            let n = prev.missCount + 1
            if n >= missThreshold { return State(presence: .missing, missCount: n) }
            // Below threshold: keep the session Active while we accumulate misses.
            return State(presence: .present, missCount: n)
        }
    }
}

// MARK: - Terminal session lookup (typed focus result)

struct TerminalTabReference: Equatable { var tty: String }

/// Typed outcome of trying to locate/focus a session's terminal tab. Replaces a
/// boolean so the UI can show a REASON-accurate message and never mislabels a
/// transient/permission/unknown failure as a confirmed-closed terminal.
enum TerminalSessionLookupResult: Equatable {
    case found(TerminalTabReference)
    case ttyNotFound                 // enumeration succeeded, tab not currently matched
    case missingSessionTTY           // session never captured a TTY
    case automationPermissionDenied  // Automation consent not granted
    case terminalNotRunning          // Terminal.app actually gone
    case enumerationFailed(String)   // AppleScript error / timeout / malformed
    case unsupportedTerminal(String) // e.g. iTerm — not precisely scriptable here
}

/// Pure mapping from a lookup result to the user-facing message. `.missing`
/// (three confirmed misses) or Terminal termination are the ONLY cases that show
/// "no longer available"; every other failure gets a precise, non-alarming
/// reason and the session stays Active.
enum TerminalFocusFeedback {
    static let unavailable = "Original terminal tab is no longer open"
    static let permissionDenied = "Terminal Automation permission required"
    static let verifyFailed = "Terminal query failed"
    static let notLinked = "Terminal identifier unavailable"
    static let temporary = unavailable
    static let unsupported = "Terminal application not supported"
    static let notRunning = "Terminal.app is not running"
    static let focused = "Terminal tab focused"

    /// Returns nil when the tab was found (no message needed).
    static func message(for result: TerminalSessionLookupResult,
                        presence: AgentTerminalPresence) -> String? {
        switch result {
        case .found: return nil
        case .automationPermissionDenied: return permissionDenied
        case .missingSessionTTY: return notLinked
        case .enumerationFailed: return verifyFailed
        case .unsupportedTerminal: return unsupported
        case .terminalNotRunning: return notRunning
        case .ttyNotFound:
            return unavailable
        }
    }
}

// MARK: - Terminal focus (existing tab by TTY — never a new window)

enum TerminalFocus {
    static let unavailableMessage = "The original terminal session is no longer available"

    /// Normalise a TTY to a full device path (e.g. "ttys003" → "/dev/ttys003").
    static func normalizeTTY(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return t }
        return t.hasPrefix("/dev/") ? t : "/dev/\(t)"
    }

    /// AppleScript that returns the TTY of every open Terminal.app tab, comma
    /// separated. Read-only enumeration — never creates windows or runs commands.
    static func enumerateTTYsScript() -> String {
        """
        tell application "Terminal"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & (tty of t) & ","
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
    }

    /// AppleScript that focuses the EXISTING tab whose TTY matches, raises and
    /// unminimises its window, and activates Terminal. Contains no `do script`,
    /// no `open`, no new window/tab creation.
    static func focusTTYScript(tty: String) -> String {
        let target = normalizeTTY(tty)
        return """
        with timeout of 5 seconds
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (tty of t) is "\(target)" then
                                set selected of t to true
                                set frontmost of w to true
                                if miniaturized of w then set miniaturized of w to false
                                activate
                                return "ok"
                            end if
                        end try
                    end repeat
                end repeat
            end tell
        end timeout
        return "notfound"
        """
    }

    /// Parse the enumeration output into a normalised TTY set.
    static func parseTTYList(_ output: String) -> Set<String> {
        Set(output.split(separator: ",")
            .map { normalizeTTY(String($0)) }
            .filter { $0.hasPrefix("/dev/tty") })
    }

    /// Safety audit for tests: a focus script must never spawn or run anything.
    static func isSafeFocusScript(_ script: String) -> Bool {
        let banned = ["do script", "open -a", "open application", "tell application \"System Events\" to keystroke"]
        let lower = script.lowercased()
        return !banned.contains { lower.contains($0) }
    }
}

// MARK: - Provider identity

/// Distinct provider vendors NotchDeck can recognise.
enum AgentVendor: String, CaseIterable, Codable, Equatable {
    case claudeCode, codex, gemini, copilot, cursor, aider, opencode, unknown

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .copilot: return "GitHub Copilot CLI"
        case .cursor: return "Cursor Agent"
        case .aider: return "Aider"
        case .opencode: return "OpenCode"
        case .unknown: return "Agent"
        }
    }

    /// Original polished monogram used when no bundled asset applies.
    var monogram: String {
        switch self {
        case .claudeCode: return "C"
        case .codex: return "CX"
        case .gemini: return "G"
        case .copilot: return "CP"
        case .cursor: return "CR"
        case .aider: return "A"
        case .opencode: return "OC"
        case .unknown: return "»_"
        }
    }

    /// Generic SF fallback glyph (only for unknown / asset-less providers).
    var fallbackSymbol: String {
        self == .unknown ? "terminal" : "chevron.left.forwardslash.chevron.right"
    }

    var accent: AgentAccentRole {
        switch self {
        case .claudeCode: return .claude
        case .codex: return .codex
        case .gemini: return .gemini
        case .copilot: return .copilot
        case .cursor: return .cursor
        case .aider: return .aider
        case .opencode: return .opencode
        case .unknown: return .neutral
        }
    }

    var accessibilityLabel: String { "\(displayName) logo" }
    /// Short name for compact space (never truncated mid-word).
    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .aider: return "Aider"
        case .opencode: return "OpenCode"
        case .unknown: return "Agent"
        }
    }

    /// Bundled asset base names (light = white logo, dark = black logo). nil when
    /// no distributable asset is supplied — the monogram is used instead.
    var assetLight: String? {
        switch self {
        case .claudeCode: return "AgentLogoClaudeLight"
        case .codex: return "AgentLogoCodexLight"
        case .gemini: return "AgentLogoGemini"
        default: return nil
        }
    }
    var assetDark: String? {
        switch self {
        case .claudeCode: return "AgentLogoClaudeDark"
        case .codex: return "AgentLogoCodexDark"
        case .gemini: return "AgentLogoGemini"   // single supplied variant
        default: return nil
        }
    }

    /// Resolve from the app provider kind, sniffing a text hint for externals.
    static func resolve(kind: AgentProviderKind, hint: String?) -> AgentVendor {
        switch kind {
        case .claudeCode: return .claudeCode
        case .codex: return .codex
        case .external: break
        }
        let l = (hint ?? "").lowercased()
        if l.contains("claude") { return .claudeCode }
        if l.contains("codex") || l.contains("chatgpt") { return .codex }
        if l.contains("gemini") { return .gemini }
        if l.contains("copilot") { return .copilot }
        if l.contains("cursor") { return .cursor }
        if l.contains("aider") { return .aider }
        if l.contains("opencode") { return .opencode }
        return .unknown
    }
}

/// Restrained accent role (colour resolved in the SwiftUI layer).
enum AgentAccentRole: String, Equatable {
    case claude, codex, gemini, copilot, cursor, aider, opencode, neutral
}

/// Data-driven provider appearance entry.
struct AgentProviderAppearance: Equatable {
    let vendor: AgentVendor
    let displayName: String
    let assetLight: String?
    let assetDark: String?
    let monogram: String
    let fallbackSymbol: String
    let accent: AgentAccentRole
    let accessibilityLabel: String

    /// Asset name for an effective background: dark background → white (light)
    /// logo; light background → black (dark) logo.
    func assetName(darkBackground: Bool) -> String? {
        darkBackground ? assetLight : (assetDark ?? assetLight)
    }
}

/// Central registry — completely data-driven from `AgentVendor`.
enum AgentProviderAppearanceRegistry {
    static func appearance(_ vendor: AgentVendor) -> AgentProviderAppearance {
        AgentProviderAppearance(
            vendor: vendor,
            displayName: vendor.displayName,
            assetLight: vendor.assetLight,
            assetDark: vendor.assetDark,
            monogram: vendor.monogram,
            fallbackSymbol: vendor.fallbackSymbol,
            accent: vendor.accent,
            accessibilityLabel: vendor.accessibilityLabel)
    }

    static func appearance(kind: AgentProviderKind, hint: String?) -> AgentProviderAppearance {
        appearance(AgentVendor.resolve(kind: kind, hint: hint))
    }
}

// MARK: - Permission handling modes

enum AgentPermissionHandlingMode: String, Codable, CaseIterable, Identifiable {
    case terminalOnly
    case notchWithTerminalFallback
    case notchOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .terminalOnly: return "Terminal only"
        case .notchWithTerminalFallback: return "NotchDeck, then Terminal fallback"
        case .notchOnly: return "NotchDeck only"
        }
    }
    /// Whether NotchDeck shows functional Allow/Deny.
    var showsFunctionalDecision: Bool { self != .terminalOnly }
    /// Whether a native terminal prompt is expected to appear.
    var nativePromptExpected: Bool { self != .notchOnly }
}

enum TerminalFallbackDelay: String, Codable, CaseIterable, Identifiable {
    case s3, s5, s8, s15
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self { case .s3: return 3; case .s5: return 5; case .s8: return 8; case .s15: return 15 }
    }
    var label: String { "\(Int(seconds)) seconds" }
}

// MARK: - Approval classification & pending model

/// Classifies incoming bridge events strictly: only a genuine PermissionRequest
/// creates an approval. PreToolUse (toolStarted) is ONLY activity.
enum ApprovalClassifier {
    static func createsApproval(_ type: TerminalAgentEventType) -> Bool {
        type == .permissionRequested
    }
    /// Events that clear/resolve a live approval.
    static func clearsApproval(_ type: TerminalAgentEventType) -> Bool {
        switch type {
        case .toolCompleted, .agentStopped, .sessionEnded: return true
        default: return false
        }
    }
    static func reason(_ type: TerminalAgentEventType) -> String {
        switch type {
        case .toolPermissionRequested: return "Legacy PreToolUse decision → released to native flow"
        case .permissionRequested: return "PermissionRequest → correlated human decision"
        case .toolStarted: return "PreToolUse activity → activity only, never approval"
        case .toolCompleted: return "PostToolUse → tool completed, clears approval"
        case .agentStopped: return "Stop → turn finished, clears approval"
        case .sessionEnded: return "SessionEnd → session finished, clears approval"
        default: return "\(type.rawValue) → activity"
        }
    }
}

/// Explicit pending-approval object keyed by provider request identity.
struct PendingApproval: Equatable, Codable {
    /// Delivery lifecycle. "Approved" (delivered) means the decision actually
    /// reached the live helper's stdout — never merely a UI click.
    /// Truthful delivery lifecycle. NB: a socket write / a helper `responseWritten`
    /// ack proves only that bytes were emitted — NOT that the provider accepted
    /// them. "Claude continued" (`delivered`) is set ONLY when real provider
    /// progression is observed (the gated tool actually ran).
    enum ResponseState: String, Codable, Equatable {
        case pending          // "Waiting for decision" — awaiting the user
        case sending          // "Sending to Claude" — decision being written to the helper
        case sent             // "Sent to Claude" — response written+flushed, provider not yet confirmed
        case helperExited     // provider-facing stdout closed; provider acceptance not yet observed
        case delivered        // "Claude continued" — provider progression observed
        case deliveryFailed   // "Delivery failed" — helper gone / write failed
        case fellBack         // "Released to Terminal" — hybrid deadline → native prompt
        case expired          // decided too late / timed out
        case cancelled
        // Back-compat: a plain "answered" maps onto delivered semantics.
        case answered
    }
    var provider: AgentProviderKind
    var sessionID: String
    /// NotchDeck transaction identity, unique per live helper invocation.
    var requestID: String
    /// Provider-native request key retained separately. It never owns a socket.
    var providerRequestID: String? = nil
    var toolUseID: String?
    var turnID: String?
    /// Exact raw hook event name that produced this approval.
    var rawEventName: String
    var toolName: String?
    var summary: String
    var receivedAt: Date
    var expiresAt: Date
    var state: ResponseState
    var handlingMode: AgentPermissionHandlingMode
    /// When (in hybrid mode) the helper stops waiting and the native prompt shows.
    var fallbackDeadline: Date?
    var nativePromptExpected: Bool
    /// The user's decision, recorded when it is written to the helper (state
    /// `.sending`) so the delivery acknowledgement can apply the correct session
    /// status only after real delivery — never on the click alone.
    var decidedAllow: Bool? = nil

    var isLive: Bool { state == .pending }
    func isExpired(now: Date) -> Bool { now >= expiresAt }
    func fallbackRemaining(now: Date) -> TimeInterval? {
        guard let d = fallbackDeadline else { return nil }
        return max(0, d.timeIntervalSince(now))
    }
}

// MARK: - Latest message resolution & sanitisation

enum AgentLatestMessage {
    static let maxChars = 400

    /// Ordered source priority → sanitized summary. Never throws; falls back to
    /// the status label so a schema change degrades gracefully.
    static func resolve(lastAssistantMessage: String?, eventSummary: String?,
                        toolAction: String?, transcriptTail: String?,
                        status: AgentSessionStatus) -> String {
        for candidate in [lastAssistantMessage, eventSummary, toolAction, transcriptTail] {
            if let c = candidate {
                let s = sanitize(c)
                if !s.isEmpty { return s }
            }
        }
        return status.label
    }

    /// Strip escape codes, control chars, redact secrets, drop raw JSON, cap length.
    static func sanitize(_ raw: String) -> String {
        var text = raw
        // ANSI / terminal escape sequences (real ESC scalar in the pattern — ICU
        // does not accept \u{1B} brace syntax).
        text = regexReplace(text, "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", "")
        // Other control characters (keep normal whitespace).
        text = String(text.unicodeScalars.filter { $0 == " " || $0 == "\n" || $0 == "\t" || $0.value >= 0x20 })
        // Refuse raw JSON blobs.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "" }
        // Redact common secrets.
        for pattern in [
            #"sk-[A-Za-z0-9_\-]{6,}"#,
            #"gh[pousr]_[A-Za-z0-9]{10,}"#,
            #"AKIA[0-9A-Z]{10,}"#,
            #"(?i)bearer\s+[A-Za-z0-9._\-]{6,}"#,
            #"(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+"#
        ] {
            text = regexReplace(text, pattern, "•••")
        }
        // Collapse whitespace.
        text = regexReplace(text, #"\s+"#, " ").trimmingCharacters(in: .whitespaces)
        if text.count > maxChars { text = String(text.prefix(maxChars - 1)) + "…" }
        return text
    }

    private static func regexReplace(_ s: String, _ pattern: String, _ repl: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: repl)
    }
}

/// Best-effort transcript tail reader — version-independent, fails to nil.
enum AgentTranscript {
    static func tail(path: String?, maxChars: Int = 400) -> String? {
        guard let path, let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.suffix(maxChars))
    }
}

// MARK: - Compact live-activity model

enum CompactAgentsDisplay: String, Codable, CaseIterable, Identifiable {
    case hidden, activeCount, providerStatus, elapsed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hidden: return "Hidden"
        case .activeCount: return "Active count"
        case .providerStatus: return "Provider + status"
        case .elapsed: return "Elapsed time"
        }
    }
}

enum AgentCompactAccent: String, Codable, CaseIterable, Identifiable {
    case neutral, orange
    var id: String { rawValue }
    var label: String { self == .neutral ? "Neutral" : "Orange" }
}

enum RecentSessionLimit: String, Codable, CaseIterable, Identifiable {
    case off, five, ten, twenty
    var id: String { rawValue }
    var limit: Int { switch self { case .off: return 0; case .five: return 5; case .ten: return 10; case .twenty: return 20 } }
    var label: String { self == .off ? "Off" : "\(limit)" }
}

/// Pure compact-agents string/priority resolver. Elapsed is NEVER the default.
struct AgentCompactModel: Equatable {
    enum Kind: Int { case approval = 0, input = 1, active = 2, completed = 3 }
    var kind: Kind
    var text: String
    var glyphVendors: [AgentVendor]   // up to two, then +N handled by view
    var extraCount: Int               // N for "+N"
    var attention: Bool
    var exclusive: Bool
}

/// De-duplication of a plain external window against a connected bridge session
/// by PID / TTY / project-title association.
enum AgentSessionMerge {
    static func externalDuplicatesConnected(external: AgentSession, connected: AgentSession) -> Bool {
        let externalVendor = external.vendor
        let authoritativeVendor = connected.vendor
        if externalVendor != .unknown,
           authoritativeVendor != .unknown,
           externalVendor != authoritativeVendor {
            return false
        }
        if let ep = external.pid, let cp = connected.pid, ep == cp { return true }
        if let et = external.terminalTTY, let ct = connected.terminalTTY, !et.isEmpty, et == ct { return true }
        if let title = external.externalWindowTitle, !connected.projectName.isEmpty,
           title.localizedCaseInsensitiveContains(connected.projectName) { return true }
        return false
    }
}

/// Semantic compact-approval label chosen by available width — never character
/// truncation. Widest→narrowest variants, dropping the overflow, then the
/// countdown, then the word "approval".
enum CompactApprovalLabel {
    /// - remainingSeconds: countdown to terminal fallback (nil when none).
    /// - availableWidth: right-wing width already net of notch inset / paddings.
    static func text(vendor: AgentVendor, remainingSeconds: Int?, availableWidth: CGFloat) -> String {
        let name = vendor.shortName
        // Ideal: "Claude approval" needs the most room.
        if availableWidth >= 120 { return "\(name) approval" }
        // Countdown variant: "Claude · 7s".
        if let s = remainingSeconds, availableWidth >= 78 { return "\(name) · \(s)s" }
        // Narrowest whole variant: just the provider name (never a fragment).
        return name
    }
}

enum AgentCompactActivity {
    /// - approval/input/completed: the single most relevant session, if any.
    static func resolve(activeVendors: [AgentVendor],
                        approvalVendor: AgentVendor?, inputVendor: AgentVendor?,
                        completedProject: String?,
                        display: CompactAgentsDisplay,
                        elapsedText: String?) -> AgentCompactModel? {
        if let v = approvalVendor {
            return AgentCompactModel(kind: .approval, text: "\(v.displayName) needs approval",
                                     glyphVendors: [v], extraCount: 0, attention: true, exclusive: true)
        }
        if let v = inputVendor {
            return AgentCompactModel(kind: .input, text: "Input needed",
                                     glyphVendors: [v], extraCount: 0, attention: true, exclusive: true)
        }
        if !activeVendors.isEmpty {
            if display == .hidden { return nil }
            let shown = Array(activeVendors.prefix(2))
            let extra = max(0, activeVendors.count - shown.count)
            let text: String
            switch display {
            case .activeCount:
                text = activeVendors.count == 1 ? "\(activeVendors[0].displayName) active"
                                                : "\(activeVendors.count) agents active"
            case .providerStatus:
                text = activeVendors.count == 1 ? "\(activeVendors[0].displayName) running"
                                                : "\(activeVendors.count) running"
            case .elapsed:
                text = elapsedText ?? "\(activeVendors.count) active"
            case .hidden:
                return nil
            }
            return AgentCompactModel(kind: .active, text: text, glyphVendors: shown,
                                     extraCount: extra, attention: false, exclusive: false)
        }
        if let project = completedProject {
            return AgentCompactModel(kind: .completed, text: "\(project) done",
                                     glyphVendors: [], extraCount: 0, attention: false, exclusive: false)
        }
        return nil
    }
}

import AppKit

/// Focuses the EXISTING terminal tab/window where an agent is running, and probes
/// which terminal tabs are still open (for lifecycle presence). Terminal.app is
/// driven via read-only / focus-only AppleScript — never `do script`, never a new
/// window/tab, never relaunching the agent.
///
/// AppleScript against Terminal requires the user's Automation consent
/// (NSAppleEventsUsageDescription); failures degrade gracefully to `false`.
struct TerminalController {
    /// Bundle ids we know how to drive precisely.
    static let terminalBundleID = "com.apple.Terminal"

    /// Locate and focus the exact tab, returning a typed result so the caller can
    /// show a reason-accurate message. Never activates an unrelated window.
    func lookup(session: AgentSession) -> TerminalSessionLookupResult {
        guard isTerminalApp(session) else {
            return .unsupportedTerminal(session.terminalAppName ?? "terminal")
        }
        guard let tty = session.terminalTTY, !tty.isEmpty else { return .missingSessionTTY }
        guard terminalRunning() else { return .terminalNotRunning }

        // Every click enumerates the CURRENT Terminal state (indexes are never
        // persisted) and matches by EXACT canonical TTY via the shared matcher —
        // the same inventory + matcher terminal presence uses.
        switch inventoryDetailed() {
        case .permissionDenied:
            return .automationPermissionDenied
        case .failure(let reason):
            return .enumerationFailed(reason)
        case .success(let tabs):
            guard TerminalTabMatching.match(tty: tty, in: tabs) != nil else {
                AgentApprovalDiagnostics.recordTerminal("focus: no exact tab for \(TerminalTabMatching.canonical(tty))")
                return .ttyNotFound   // definitive no-match (enumeration succeeded)
            }
            // Actuate: select the exact existing tab, raise/unminimise its window,
            // activate Terminal. No new window/tab, no `do script`, no clipboard.
            switch runAppleScriptDetailed(TerminalFocus.focusTTYScript(tty: tty)) {
            case .success(let out):
                if out.contains("ok") {
                    AgentApprovalDiagnostics.recordTerminal("focus: selected \(TerminalTabMatching.canonical(tty))")
                    return .found(TerminalTabReference(tty: TerminalTabMatching.canonical(tty)))
                }
                return .ttyNotFound
            case .permissionDenied: return .automationPermissionDenied
            case .failure(let reason): return .enumerationFailed(reason)
            }
        }
    }

    /// A fresh, structured inventory of every Terminal window/tab. `queryError`
    /// (Automation/timeout/malformed) stays DISTINCT from a successful-but-empty
    /// result so a transient failure never marks a running session Recent.
    func inventory() -> [TerminalTabDescriptor] {
        if case .success(let tabs) = inventoryDetailed() { return tabs }
        return []
    }

    private enum InventoryOutcome: Equatable {
        case success([TerminalTabDescriptor])
        case permissionDenied
        case failure(String)
    }

    private func inventoryDetailed() -> InventoryOutcome {
        switch runAppleScriptDetailed(TerminalTabInventory.script()) {
        case .success(let out): return .success(TerminalTabInventory.parse(out))
        case .permissionDenied: return .permissionDenied
        case .failure(let reason): return .failure(reason)
        }
    }

    /// Convenience boolean (kept for existing callers).
    func focus(session: AgentSession) -> Bool {
        if case .found = lookup(session: session) { return true }
        return false
    }

    /// Result of one tab enumeration. `queryError` (AppleScript/permission/timeout/
    /// malformed) is kept DISTINCT from a successful-but-empty result so the
    /// debouncer never counts an error as a confirmed miss.
    enum EnumerationResult: Equatable {
        case success(Set<String>)
        case queryError
        case terminalNotRunning
    }

    func enumerate() -> EnumerationResult {
        guard terminalRunning() else { return .terminalNotRunning }
        // Same structured inventory + canonical matcher Focus Terminal uses, so
        // presence and focus can never disagree about whether a tab exists.
        switch inventoryDetailed() {
        case .success(let tabs): return .success(TerminalTabMatching.ttySet(tabs))
        case .permissionDenied, .failure: return .queryError
        }
    }

    /// The set of TTYs currently open in Terminal.app tabs (empty on error).
    func activeTerminalTTYs() -> Set<String> {
        if case .success(let set) = enumerate() { return set }
        return []
    }

    /// Map an enumeration result to a single-session observation for the debouncer.
    func observation(for session: AgentSession, result: EnumerationResult) -> TerminalObservation {
        switch result {
        case .terminalNotRunning:
            return .appTerminated
        case .queryError:
            return .queryError
        case .success(let ttys):
            guard let tty = session.terminalTTY, !tty.isEmpty else { return .queryError } // can't confirm
            return ttys.contains(TerminalFocus.normalizeTTY(tty)) ? .present : .absent
        }
    }

    // MARK: Helpers

    private func isTerminalApp(_ session: AgentSession) -> Bool {
        if session.terminalBundleID == Self.terminalBundleID { return true }
        let name = (session.terminalAppName ?? "").lowercased()
        return name.contains("terminal") && !name.contains("iterm")
    }

    private func terminalRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.terminalBundleID).isEmpty
    }

    /// Detailed AppleScript execution outcome (distinguishes Automation denial).
    enum ScriptOutcome: Equatable {
        case success(String)
        case permissionDenied
        case failure(String)
    }

    /// AppleScript Automation-denied / not-authorised error numbers.
    private static let permissionErrorNumbers: Set<Int> = [-1743, -10004, -1728]

    private func runAppleScriptDetailed(_ source: String) -> ScriptOutcome {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure("invalid script") }
        let out = script.executeAndReturnError(&error)
        if let error {
            let num = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if Self.permissionErrorNumbers.contains(num) { return .permissionDenied }
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "error \(num)"
            return .failure(msg)
        }
        return .success(out.stringValue ?? "")
    }

    /// Run an AppleScript source and return its string result (nil on error).
    private func runAppleScript(_ source: String) -> String? {
        if case .success(let s) = runAppleScriptDetailed(source) { return s }
        return nil
    }
}

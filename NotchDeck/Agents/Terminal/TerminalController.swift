import AppKit

enum TerminalInventoryOutcome: Equatable {
    case success([TerminalTabDescriptor])
    case automationPermissionDenied
    case terminalNotRunning
    case queryFailed(String)
}

enum TerminalActuationOutcome: Equatable {
    case focused
    case tabClosed
    case automationPermissionDenied
    case queryFailed(String)
}

/// Injectable host boundary. Unit tests use a recorder and never launch or
/// manipulate Terminal.app.
protocol TerminalHostControlling {
    func inventory() -> TerminalInventoryOutcome
    func focusExistingTab(tty: String) -> TerminalActuationOutcome
}

struct AppleTerminalHostController: TerminalHostControlling {
    static let bundleID = "com.apple.Terminal"

    func inventory() -> TerminalInventoryOutcome {
        guard isRunning else { return .terminalNotRunning }
        switch execute(TerminalTabInventory.script()) {
        case .success(let output):
            switch TerminalTabInventory.parseDetailed(output) {
            case .success(let tabs): return .success(tabs)
            case .malformed: return .queryFailed("malformed Terminal inventory")
            }
        case .automationPermissionDenied: return .automationPermissionDenied
        case .queryFailed(let reason): return .queryFailed(reason)
        }
    }

    func focusExistingTab(tty: String) -> TerminalActuationOutcome {
        guard TerminalTTYValidator.isValid(tty) else {
            return .queryFailed("invalid terminal identifier")
        }
        switch execute(TerminalFocus.focusTTYScript(tty: tty)) {
        case .success(let output):
            switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "ok": return .focused
            case "notfound": return .tabClosed
            default: return .queryFailed("unexpected Terminal response")
            }
        case .automationPermissionDenied: return .automationPermissionDenied
        case .queryFailed(let reason): return .queryFailed(reason)
        }
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    private enum ScriptOutcome {
        case success(String)
        case automationPermissionDenied
        case queryFailed(String)
    }

    private func execute(_ source: String) -> ScriptOutcome {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .queryFailed("invalid script")
        }
        let output = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1728 is an object/query failure, not an Automation denial.
            if number == -1743 || number == -10004 {
                return .automationPermissionDenied
            }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "error \(number)"
            return .queryFailed(message)
        }
        return .success(output.stringValue ?? "")
    }
}

/// One matcher/service drives both presence and Focus Terminal. Every lookup
/// obtains a new inventory; transient tab/window indexes never escape the call.
struct TerminalController {
    static let terminalBundleID = AppleTerminalHostController.bundleID
    private let host: any TerminalHostControlling

    init(host: any TerminalHostControlling = AppleTerminalHostController()) {
        self.host = host
    }

    func lookup(session: AgentSession) -> TerminalSessionLookupResult {
        if let unsupported = explicitUnsupportedHost(session) {
            return .unsupportedTerminal(unsupported)
        }
        guard let tty = session.terminalTTY, TerminalTTYValidator.isValid(tty) else {
            return .missingSessionTTY
        }

        switch host.inventory() {
        case .terminalNotRunning:
            return .terminalNotRunning
        case .automationPermissionDenied:
            return .automationPermissionDenied
        case .queryFailed(let reason):
            return .enumerationFailed(reason)
        case .success(let tabs):
            guard TerminalTabMatching.match(tty: tty, in: tabs) != nil else {
                AgentApprovalDiagnostics.recordTerminal(
                    "focus no-match tty=\(TerminalTabMatching.canonical(tty))"
                )
                return .ttyNotFound
            }
        }

        switch host.focusExistingTab(tty: TerminalTabMatching.canonical(tty)) {
        case .focused:
            AgentApprovalDiagnostics.recordTerminal(
                "focus matched tty=\(TerminalTabMatching.canonical(tty))"
            )
            return .found(TerminalTabReference(tty: TerminalTabMatching.canonical(tty)))
        case .tabClosed:
            return .ttyNotFound
        case .automationPermissionDenied:
            return .automationPermissionDenied
        case .queryFailed(let reason):
            return .enumerationFailed(reason)
        }
    }

    func inventoryDetailed() -> TerminalInventoryOutcome { host.inventory() }

    func inventory() -> [TerminalTabDescriptor] {
        if case .success(let tabs) = host.inventory() { return tabs }
        return []
    }

    func focus(session: AgentSession) -> Bool {
        if case .found = lookup(session: session) { return true }
        return false
    }

    enum EnumerationResult: Equatable {
        case success(Set<String>)
        case queryError
        case terminalNotRunning
    }

    func enumerate() -> EnumerationResult {
        switch host.inventory() {
        case .success(let tabs): return .success(TerminalTabMatching.ttySet(tabs))
        case .terminalNotRunning: return .terminalNotRunning
        case .automationPermissionDenied, .queryFailed: return .queryError
        }
    }

    func activeTerminalTTYs() -> Set<String> {
        if case .success(let set) = enumerate() { return set }
        return []
    }

    func observation(for session: AgentSession, result: EnumerationResult) -> TerminalObservation {
        if explicitUnsupportedHost(session) != nil { return .queryError }
        switch result {
        case .terminalNotRunning:
            return .appTerminated
        case .queryError:
            return .queryError
        case .success(let ttys):
            guard let tty = session.terminalTTY, TerminalTTYValidator.isValid(tty) else {
                return .queryError
            }
            let tabs = ttys.map {
                TerminalTabDescriptor(windowIndex: 0, tabIndex: 0, tty: $0,
                                      selected: false, minimized: false)
            }
            return TerminalTabMatching.match(tty: tty, in: tabs) == nil ? .absent : .present
        }
    }

    private func explicitUnsupportedHost(_ session: AgentSession) -> String? {
        if let bundle = session.terminalBundleID, !bundle.isEmpty,
           bundle != Self.terminalBundleID {
            return session.terminalAppName ?? bundle
        }
        if let name = session.terminalAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            let lower = name.lowercased()
            if lower.contains("iterm") || lower.contains("warp") || lower.contains("ghostty")
                || lower.contains("code") || lower.contains("cursor") {
                return name
            }
        }
        return nil
    }
}

import Foundation

/// One open Terminal.app tab, captured in a single fresh enumeration. Window/tab
/// indexes are valid ONLY for the enumeration that produced them (they can change
/// as windows open/close); the durable identity is the canonical `tty`.
struct TerminalTabDescriptor: Equatable {
    var windowIndex: Int
    var tabIndex: Int
    var tty: String        // canonical, e.g. "/dev/ttys003"
    var selected: Bool
    var minimized: Bool
}

/// The ONE canonical terminal-tab matcher shared by Active/Recent presence,
/// Focus Terminal and diagnostics — so presence can never say "Active" while
/// Focus Terminal uses a different algorithm and fails to find the tab.
enum TerminalTabMatching {
    /// Canonical device-path form: "ttys003" and "/dev/ttys003" collapse to one.
    static func canonical(_ tty: String) -> String {
        let t = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return t }
        return t.hasPrefix("/dev/") ? t : "/dev/\(t)"
    }

    /// EXACT canonical equality — never a substring/prefix match, so
    /// "/dev/ttys01" can never match "/dev/ttys010".
    static func match(tty: String, in tabs: [TerminalTabDescriptor]) -> TerminalTabDescriptor? {
        let target = canonical(tty)
        guard !target.isEmpty else { return nil }
        return tabs.first { canonical($0.tty) == target }
    }

    static func ttySet(_ tabs: [TerminalTabDescriptor]) -> Set<String> {
        Set(tabs.map { canonical($0.tty) })
    }
}

/// Builds the read-only AppleScript that enumerates every window and every tab,
/// and parses its output into `TerminalTabDescriptor`s. Contains no `do script`,
/// no `open`, no window/tab creation, no clipboard access.
enum TerminalTabInventory {
    /// Read-only enumeration of ALL windows and ALL tabs (indexes + tty +
    /// selected + minimised), one row per tab: `win|tab|tty|selected|minimized`.
    static func script() -> String {
        """
        with timeout of 5 seconds
            tell application "Terminal"
                set out to ""
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set mz to (miniaturized of w)
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        try
                            set out to out & wi & "|" & ti & "|" & (tty of t) & "|" & (selected of t) & "|" & mz & "
        "
                        end try
                    end repeat
                end repeat
                return out
            end tell
        end timeout
        """
    }

    enum ParseResult: Equatable {
        case success([TerminalTabDescriptor])
        case malformed
    }

    static func parseDetailed(_ output: String) -> ParseResult {
        let rows = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        var tabs: [TerminalTabDescriptor] = []
        for row in rows {
            let f = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5,
                  let wi = Int(f[0].trimmingCharacters(in: .whitespaces)),
                  let ti = Int(f[1].trimmingCharacters(in: .whitespaces)) else { return .malformed }
            let tty = TerminalTabMatching.canonical(f[2])
            guard TerminalTTYValidator.isValid(tty) else { return .malformed }
            func bool(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).lowercased() == "true" }
            tabs.append(TerminalTabDescriptor(windowIndex: wi, tabIndex: ti, tty: tty,
                                              selected: bool(f[3]), minimized: bool(f[4])))
        }
        return .success(tabs)
    }

    static func parse(_ output: String) -> [TerminalTabDescriptor] {
        if case .success(let tabs) = parseDetailed(output) { return tabs }
        return []
    }

    /// Safety audit for tests: the enumeration must never spawn or run anything.
    static func isReadOnlyScript(_ script: String) -> Bool {
        let banned = ["do script", "open -a", "open application", "keystroke", "set the clipboard", "the clipboard"]
        let lower = script.lowercased()
        return !banned.contains { lower.contains($0) }
    }
}

enum TerminalTTYValidator {
    static func isValid(_ raw: String) -> Bool {
        let tty = TerminalTabMatching.canonical(raw)
        guard tty.hasPrefix("/dev/tty"), tty.count > "/dev/tty".count else { return false }
        return tty.dropFirst("/dev/".count).allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-"
        }
    }
}

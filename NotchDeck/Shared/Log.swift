import Foundation
import os

/// Lightweight logging facade over `os.Logger` plus a secret sanitizer used
/// everywhere diagnostics may contain command lines, environment or output.
enum Log {
    private static let subsystem = "com.notchdeck.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let agents = Logger(subsystem: subsystem, category: "agents")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let process = Logger(subsystem: subsystem, category: "process")
}

/// Removes credentials from strings before they are shown in diagnostics or
/// persisted to rotating logs. Best-effort, deliberately conservative.
enum SecretSanitizer {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            // Authorization headers, including a "Bearer <token>" value.
            #"(?i)authorization\s*[:=]\s*(bearer\s+)?\S+"#,
            // key=value style secrets
            #"(?i)(api[_-]?key|apikey|token|secret|password|passwd|bearer|authorization|cookie)\s*[=:]\s*\S+"#,
            // Common provider token shapes
            #"sk-[A-Za-z0-9_-]{8,}"#,
            #"sk-ant-[A-Za-z0-9_-]{8,}"#,
            #"ghp_[A-Za-z0-9]{8,}"#,
            #"AKIA[0-9A-Z]{12,}"#,
            // Authorization: Bearer <...>
            #"(?i)bearer\s+[A-Za-z0-9._-]{8,}"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func redact(_ input: String) -> String {
        var output = input
        for regex in patterns {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(
                in: output, range: range, withTemplate: "«redacted»")
        }
        return output
    }

    /// Redacts a home-directory absolute path down to `~` for exported diagnostics.
    static func redactHome(_ input: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty else { return input }
        return input.replacingOccurrences(of: home, with: "~")
    }
}

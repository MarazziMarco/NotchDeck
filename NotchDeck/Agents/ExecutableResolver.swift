import Foundation

/// Resolves CLI executables. A Finder-launched app inherits a minimal PATH, so
/// we search well-known locations and, as a last resort, ask a login shell.
struct ExecutableResolver {
    /// Standard search locations, expanded for the current user.
    static var defaultSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "/usr/bin",
        ]
    }

    var overridePath: String?
    var searchPaths: [String]

    init(overridePath: String? = nil, searchPaths: [String] = ExecutableResolver.defaultSearchPaths) {
        self.overridePath = overridePath
        self.searchPaths = searchPaths
    }

    /// Locate an executable by name. Returns the first existing, executable path.
    func resolve(_ name: String) -> String? {
        if let override = overridePath, isExecutable(override) {
            return override
        }
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        // Last resort: login shell `which`, which loads the user's PATH.
        return loginShellWhich(name)
    }

    func isExecutable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    /// Ask the user's login shell to resolve a command via PATH.
    private func loginShellWhich(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // `-lic` loads login + interactive config so PATH matches a terminal.
        process.arguments = ["-lic", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let output, !output.isEmpty, isExecutable(output) { return output }
        } catch {
            Log.process.error("login-shell which failed: \(error.localizedDescription)")
        }
        return nil
    }

    /// Run `<exe> --version` and return trimmed output (best-effort).
    static func version(of executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

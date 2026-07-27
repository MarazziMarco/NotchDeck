import Foundation
import AppKit

/// Installs / removes NotchDeck's terminal hooks for Codex and Claude Code.
/// Conservative and reversible: never deletes the user's own hooks, always
/// timestamps a backup before writing, and marks its own entries so they can be
/// removed cleanly. Command strings reference the bundled helper.
enum HookInstaller {

    struct Plan: Equatable {
        var provider: TerminalAgentProvider
        var configPath: String
        var backupPath: String?
        var diff: String
    }

    enum HookError: LocalizedError {
        case helperMissing
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .helperMissing: return "The notchdeck-agent-hook helper could not be located in the app bundle."
            case .writeFailed(let d): return "Failed to write hook configuration: \(d)"
            }
        }
    }

    /// Marker embedded in every command NotchDeck adds, for safe removal.
    static let marker = "notchdeck-agent-hook"

    /// Managed hook/helper protocol version. BUMP whenever the helper's provider
    /// response schema or the timeout constants change, so `configIsUpToDate`
    /// returns false for an older installation and the integration UI prompts
    /// Reinstall Hooks (replacing only NotchDeck-managed entries; user hooks and
    /// backups are preserved).
    ///
    /// v2: PermissionRequest response corrected to the provider-valid
    /// `hookSpecificOutput.permissionDecision` schema (was `decision:{behavior}`).
    static let managedHookVersion = 2
    static let managedVersionKey = "notchdeckHookVersion"

    // MARK: Helper install

    static var installedHelperURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("notchdeck-agent-hook")
    }

    static func bundledHelperURL() -> URL? {
        let bundle = Bundle.main
        // Embedded as a bundled executable (Contents/Helpers) or auxiliary exec.
        if let url = bundle.url(forAuxiliaryExecutable: "notchdeck-agent-hook") { return url }
        let candidates = [
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/notchdeck-agent-hook"),
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/notchdeck-agent-hook"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Copy the helper into Application Support and make it executable.
    @discardableResult
    static func ensureHelperInstalled() throws -> URL {
        guard let source = bundledHelperURL() else { throw HookError.helperMissing }
        let dest = installedHelperURL
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }

    // MARK: Config locations

    private static func configURL(for provider: TerminalAgentProvider) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .unknown: return home.appendingPathComponent(".notchdeck/unknown.json")
        }
    }

    /// The event → command entries NotchDeck adds, keyed by the provider's hook
    /// event names.
    private static func entries(for provider: TerminalAgentProvider, helper: String)
        -> [(hookEvent: String, event: TerminalAgentEventType, matcher: Bool)] {
        // Strict split: PermissionRequest is the ONLY approval hook; PreToolUse is
        // non-blocking activity monitoring and must NEVER map to permissionRequested.
        switch provider {
        case .codex:
            return [
                ("SessionStart", .sessionStarted, false),
                ("PreToolUse", .toolStarted, true),          // activity only
                ("PermissionRequest", .permissionRequested, false),
                ("PostToolUse", .toolCompleted, false),
                ("Stop", .agentStopped, false),
                ("SessionEnd", .sessionEnded, false),
            ]
        case .claudeCode:
            return [
                ("SessionStart", .sessionStarted, false),
                ("PreToolUse", .toolStarted, true),          // activity only (was wrongly permission)
                ("PermissionRequest", .permissionRequested, true),
                ("PostToolUse", .toolCompleted, true),
                ("Stop", .agentStopped, false),
                ("SessionEnd", .sessionEnded, false),
            ]
        case .unknown:
            return []
        }
    }

    /// Build the hook command string. The helper path is DOUBLE-QUOTED because
    /// the installed path contains a space ("Application Support"); unquoted it
    /// would be split by `sh -c` (how Codex/Claude run command hooks) and fail
    /// with exit 127. The path is absolute (resolved home, no tilde). The
    /// provider is passed by its CLI name (`claude` / `codex`).
    static func command(helper: String, provider: TerminalAgentProvider,
                        event: TerminalAgentEventType) -> String {
        "\"\(helper)\" --provider \(provider.cliName) --event \(event.rawValue)"
    }

    // MARK: Read / write JSON

    private static func loadJSON(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        AppPaths.ensureDirectory(url.deletingLastPathComponent())
        let data = try JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .sortedKeys])
        do { try data.write(to: url, options: [.atomic]) }
        catch { throw HookError.writeFailed(error.localizedDescription) }
    }

    private static func backup(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.appendingPathExtension("notchdeck-backup-\(stamp)")
        try? FileManager.default.copyItem(at: url, to: backup)
        return backup.path
    }

    // MARK: Public API

    static func isInstalled(_ provider: TerminalAgentProvider) -> Bool {
        hasMarker(in: loadJSON(configURL(for: provider)), provider: provider)
    }

    /// True when the installed NotchDeck PermissionRequest hook matches the
    /// current expected schema (managed marker) and timeout. Pure over a config
    /// dict for testability.
    static func configIsUpToDate(_ json: [String: Any], provider: TerminalAgentProvider) -> Bool {
        guard let hooks = hooksDictionary(json, provider: provider),
              let entries = hooks["PermissionRequest"] as? [[String: Any]] else { return false }
        let managed = entries.filter { containsMarker($0) }
        guard managed.count == 1, let inner = (managed[0]["hooks"] as? [[String: Any]])?.first else { return false }
        if inner["async"] != nil { return false }
        guard (inner["timeout"] as? Int) == HookTimeouts.claudeHookTimeoutSeconds else { return false }
        // A stale response-schema/timeout install lacks the current version marker.
        return (inner[managedVersionKey] as? Int) == managedHookVersion
    }

    /// True when NotchDeck hooks are installed but STALE (wrong timeout/schema or
    /// duplicates) → the UI should prompt the user to reinstall.
    static func needsReinstall(_ provider: TerminalAgentProvider) -> Bool {
        let json = loadJSON(configURL(for: provider))
        guard hasMarker(in: json, provider: provider) else { return false }
        return !configIsUpToDate(json, provider: provider)
    }

    /// Human-readable preview of what will change (the merged hook block).
    static func preview(_ provider: TerminalAgentProvider) throws -> String {
        let helper = installedHelperURL.path
        let merged = try mergedConfig(provider: provider, helper: helper)
        let data = try JSONSerialization.data(withJSONObject: merged,
                                              options: [.prettyPrinted, .sortedKeys])
        let path = SecretSanitizer.redactHome(configURL(for: provider).path)
        return "Will update \(path):\n\n" + (String(data: data, encoding: .utf8) ?? "")
    }

    @discardableResult
    static func install(_ provider: TerminalAgentProvider) throws -> Plan {
        let helperURL = try ensureHelperInstalled()
        let url = configURL(for: provider)
        let backupPath = backup(url)
        let merged = try mergedConfig(provider: provider, helper: helperURL.path)
        try writeJSON(merged, to: url)
        return Plan(provider: provider,
                    configPath: SecretSanitizer.redactHome(url.path),
                    backupPath: backupPath.map(SecretSanitizer.redactHome),
                    diff: "Installed \(entries(for: provider, helper: helperURL.path).count) hooks.")
    }

    static func uninstall(_ provider: TerminalAgentProvider) throws {
        let url = configURL(for: provider)
        _ = backup(url)
        let json = removeHooks(base: loadJSON(url), provider: provider)
        try writeJSON(json, to: url)
    }

    // MARK: Merge core (pure enough to unit-test via public shims)

    static func mergedConfig(provider: TerminalAgentProvider, helper: String) throws -> [String: Any] {
        mergeHooks(base: loadJSON(configURL(for: provider)), provider: provider, helper: helper)
    }

    /// Pure merge: add NotchDeck's hook entries into `base`, preserving the
    /// user's existing hooks and avoiding duplicates. Unit-testable (no disk).
    static func mergeHooks(base: [String: Any], provider: TerminalAgentProvider,
                           helper: String) -> [String: Any] {
        var json = base
        var hooks = hooksDictionary(json, provider: provider) ?? [:]
        for spec in entries(for: provider, helper: helper) {
            let cmd = command(helper: helper, provider: provider, event: spec.event)
            // PermissionRequest must be SYNCHRONOUS: no `async`, and a timeout
            // longer than the app's 8s UI fallback so the user has time to choose.
            var hookDict: [String: Any] = ["type": "command", "command": cmd, managedKey: true,
                                           managedVersionKey: managedHookVersion]
            if spec.event == .permissionRequested { hookDict["timeout"] = HookTimeouts.claudeHookTimeoutSeconds }
            var entry: [String: Any] = ["hooks": [hookDict], managedKey: true]
            if spec.matcher { entry["matcher"] = "*" }
            var array = (hooks[spec.hookEvent] as? [[String: Any]]) ?? []
            // Remove ALL prior NotchDeck-managed entries for this event so exactly
            // one active PermissionRequest hook remains (no duplicates).
            array.removeAll { containsMarker($0) }
            array.append(entry)
            hooks[spec.hookEvent] = array
        }
        setHooksDictionary(&json, hooks, provider: provider)
        return json
    }

    /// Pure removal: strip every NotchDeck-added hook entry, leaving the user's.
    static func removeHooks(base: [String: Any], provider: TerminalAgentProvider) -> [String: Any] {
        var json = base
        guard var hooks = hooksDictionary(json, provider: provider) else { return json }
        for (key, value) in hooks {
            guard var array = value as? [[String: Any]] else { continue }
            array.removeAll { containsMarker($0) }
            if array.isEmpty { hooks[key] = nil } else { hooks[key] = array }
        }
        setHooksDictionary(&json, hooks, provider: provider)
        return json
    }

    /// Whether `json` already contains NotchDeck hook entries. Unit-testable.
    static func hasMarker(in json: [String: Any], provider: TerminalAgentProvider) -> Bool {
        guard let hooks = hooksDictionary(json, provider: provider) else { return false }
        return hooks.values.contains { array in
            (array as? [[String: Any]])?.contains { containsMarker($0) } ?? false
        }
    }

    /// Codex keeps hooks at the top level of hooks.json; Claude nests them under
    /// a "hooks" key in settings.json.
    private static func hooksDictionary(_ json: [String: Any], provider: TerminalAgentProvider) -> [String: Any]? {
        switch provider {
        case .claudeCode: return json["hooks"] as? [String: Any] ?? [:]
        default: return json
        }
    }

    private static func setHooksDictionary(_ json: inout [String: Any], _ hooks: [String: Any],
                                           provider: TerminalAgentProvider) {
        switch provider {
        case .claudeCode: json["hooks"] = hooks
        default: json = hooks
        }
    }

    // MARK: Diagnostics / validation

    struct ValidationCheck: Identifiable {
        let id = UUID()
        var name: String
        var ok: Bool
        var detail: String
    }

    static func configPath(for provider: TerminalAgentProvider) -> String {
        configURL(for: provider).path
    }

    static func openConfigFile(_ provider: TerminalAgentProvider) {
        let url = configURL(for: provider)
        AppPaths.ensureDirectory(url.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "{}".data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    /// Validate the whole terminal-integration setup for a provider, returning
    /// specific pass/fail checks instead of a vague "Offline".
    static func validate(_ provider: TerminalAgentProvider, socketExists: Bool) -> [ValidationCheck] {
        var checks: [ValidationCheck] = []
        let fm = FileManager.default

        // Config file
        let cfg = configURL(for: provider)
        let cfgExists = fm.fileExists(atPath: cfg.path)
        checks.append(.init(name: "Config file", ok: cfgExists,
                            detail: SecretSanitizer.redactHome(cfg.path)))

        // JSON validity
        if cfgExists {
            let data = (try? Data(contentsOf: cfg)) ?? Data()
            let valid = (try? JSONSerialization.jsonObject(with: data)) != nil || data.isEmpty
            checks.append(.init(name: "Valid JSON", ok: valid,
                                detail: valid ? "parses" : "malformed JSON"))
        }

        // Hooks installed
        checks.append(.init(name: "Hooks installed", ok: isInstalled(provider),
                            detail: isInstalled(provider) ? "NotchDeck entries present" : "not installed"))

        // Helper present + executable
        let helper = installedHelperURL
        let helperExists = fm.fileExists(atPath: helper.path)
        let helperExec = fm.isExecutableFile(atPath: helper.path)
        checks.append(.init(name: "Helper installed", ok: helperExists && helperExec,
                            detail: SecretSanitizer.redactHome(helper.path)
                                + (helperExists ? (helperExec ? " (executable)" : " (NOT executable)") : " (missing)")))

        // Bundled helper resolvable (for reinstall)
        checks.append(.init(name: "Bundled helper", ok: bundledHelperURL() != nil,
                            detail: bundledHelperURL().map { SecretSanitizer.redactHome($0.path) } ?? "not found in app bundle"))

        // Socket
        checks.append(.init(name: "Bridge socket", ok: socketExists,
                            detail: socketExists ? "active" : "not listening"))

        return checks
    }

    static func diagnosticReport(_ provider: TerminalAgentProvider, socketExists: Bool) -> String {
        var lines = ["NotchDeck terminal integration — \(provider.rawValue)"]
        for c in validate(provider, socketExists: socketExists) {
            lines.append("[\(c.ok ? "OK" : "!!")] \(c.name): \(c.detail)")
        }
        return lines.joined(separator: "\n")
    }

    /// Stable managed-entry identifier (independent of the helper path).
    static let managedKey = "notchdeckManaged"

    private static func containsMarker(_ entry: [String: Any]) -> Bool {
        if entry[managedKey] as? Bool == true { return true }
        if let inner = entry["hooks"] as? [[String: Any]] {
            if inner.contains(where: { $0[managedKey] as? Bool == true }) { return true }
            return inner.contains { ($0["command"] as? String)?.contains(marker) ?? false }
        }
        return (entry["command"] as? String)?.contains(marker) ?? false
    }
}

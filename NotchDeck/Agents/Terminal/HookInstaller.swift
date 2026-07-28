import Foundation
import AppKit
import Darwin

/// Installs / removes NotchDeck's terminal hooks for Codex and Claude Code.
/// Conservative and reversible: never deletes the user's own hooks, always
/// timestamps a backup before writing, and marks its own entries so they can be
/// removed cleanly. Command strings reference the bundled helper.
enum HookInstaller {
    enum HookTrustStatus: Equatable {
        case notApplicable
        case approvalRequired
        case reviewed
        case unknown
    }

    enum IntegrationState: Equatable {
        case hooksMissing
        case trustRequired
        case working
    }

    struct Plan: Equatable {
        var provider: TerminalAgentProvider
        var configPath: String
        var backupPath: String?
        var diff: String
        var changed: Bool
    }

    enum HookError: LocalizedError {
        case helperMissing
        case helperInstallFailed(String)
        case invalidConfig(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .helperMissing: return "The notchdeck-agent-hook helper could not be located in the app bundle."
            case .helperInstallFailed(let d): return "Failed to install notchdeck-agent-hook: \(d)"
            case .invalidConfig(let d): return "Hook configuration is not valid JSON: \(d)"
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
    ///     `hookSpecificOutput.permissionDecision` schema (was `decision:{behavior}`).
    /// v3: legacy PreToolUse decision experiment.
    /// v4: provider-specific PermissionRequest decision contract; PreToolUse is
    ///     enrichment only.
    /// v5: per-helper transaction identity prevents cross-session socket reuse.
    /// v6: Codex entries use the documented top-level `hooks` container and
    ///     omit private fields rejected by Codex's strict config decoder.
    static let managedHookVersion = 6
    static let managedVersionKey = "notchdeckHookVersion"

    // MARK: Helper install

    static var installedHelperURL: URL {
        resolveInstalledHelperURL(
            referencedCommands: installedManagedCommandStrings(),
            supportDirectory: AppPaths.supportDirectory
        )
    }

    static func resolveInstalledHelperURL(
        referencedCommands: [String],
        supportDirectory: URL
    ) -> URL {
        let legacy = supportDirectory.appendingPathComponent("notchdeck-agent-hook")
        let canonical = supportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("notchdeck-agent-hook")

        // Existing hook command strings are authoritative. Keeping the legacy
        // binary alive avoids breaking already-reviewed Codex hook identities.
        if referencedCommands.contains(where: { $0.contains(legacy.path) }) {
            return legacy
        }
        return canonical
    }

    static func versionURL(for helperURL: URL) -> URL {
        helperURL.appendingPathExtension("version")
    }

    static var expectedHelperVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "0"
        return "\(short)-\(build)-hook\(managedHookVersion)"
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
    static func ensureHelperInstalled(force: Bool? = nil) throws -> URL {
        guard let source = bundledHelperURL() else { throw HookError.helperMissing }
        let dest = installedHelperURL
        let defaultForce = false
        _ = try installHelper(
            from: source,
            to: dest,
            expectedVersion: expectedHelperVersion,
            force: force ?? defaultForce
        )
        return dest
    }

    /// Installs by version and executable state, never by build hash. Returns
    /// false without touching either file when the installed helper is current.
    @discardableResult
    static func installHelper(
        from source: URL,
        to destination: URL,
        expectedVersion: String,
        force: Bool
    ) throws -> Bool {
        let fm = FileManager.default
        let version = versionURL(for: destination)
        let installedVersion = try? String(contentsOf: version)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let current = fm.fileExists(atPath: destination.path)
            && fm.isExecutableFile(atPath: destination.path)
            && installedVersion == expectedVersion
        guard force || !current else { return false }

        do {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".notchdeck-agent-hook-\(UUID().uuidString).tmp")
            defer { try? fm.removeItem(at: temporary) }
            try fm.copyItem(at: source, to: temporary)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try Data("\(expectedVersion)\n".utf8).write(to: version, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: version.path)
            return true
        } catch {
            throw HookError.helperInstallFailed(error.localizedDescription)
        }
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

    private static func installedManagedCommandStrings() -> [String] {
        [.codex, .claudeCode].flatMap { provider in
            collectCommandStrings(loadJSON(configURL(for: provider)))
                .filter { $0.contains(marker) }
        }
    }

    private static func collectCommandStrings(_ value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            var commands: [String] = []
            if let command = dictionary["command"] as? String {
                commands.append(command)
            }
            return commands + dictionary.values.flatMap(collectCommandStrings)
        }
        if let array = value as? [Any] {
            return array.flatMap(collectCommandStrings)
        }
        return []
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
                ("PreToolUse", .toolStarted, true),
                ("PermissionRequest", .permissionRequested, true),
                ("PostToolUse", .toolCompleted, false),
                ("Stop", .agentStopped, false),
                ("SessionEnd", .sessionEnded, false),
            ]
        case .claudeCode:
            return [
                ("SessionStart", .sessionStarted, false),
                ("PreToolUse", .toolStarted, true),
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

    private static func backup(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let backup = url.appendingPathExtension(
            "notchdeck-backup-\(stamp)-\(UUID().uuidString.prefix(8))"
        )
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            return backup.path
        } catch {
            throw HookError.writeFailed("backup failed: \(error.localizedDescription)")
        }
    }

    private static func readConfiguration(at url: URL) throws -> ([String: Any], Data?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookError.invalidConfig("top-level value is not an object")
            }
            return (object, data)
        } catch let error as HookError {
            throw error
        } catch {
            throw HookError.invalidConfig(error.localizedDescription)
        }
    }

    // MARK: Public API

    static func isInstalled(_ provider: TerminalAgentProvider) -> Bool {
        hasMarker(in: loadJSON(configURL(for: provider)), provider: provider)
    }

    /// True when the installed NotchDeck PermissionRequest hook matches the
    /// current expected schema (managed marker) and timeout. Pure over a config
    /// dict for testability.
    static func configIsUpToDate(_ json: [String: Any], provider: TerminalAgentProvider) -> Bool {
        // PermissionRequest is the synchronous human-decision channel.
        guard let hooks = hooksDictionary(json, provider: provider),
              let entries = hooks["PermissionRequest"] as? [[String: Any]] else { return false }
        let managed = entries.filter { containsMarker($0) }
        guard managed.count == 1, let inner = (managed[0]["hooks"] as? [[String: Any]])?.first else { return false }
        if inner["async"] != nil { return false }
        guard (inner["timeout"] as? Int) == HookTimeouts.claudeHookTimeoutSeconds else { return false }
        if provider == .codex {
            // Codex rejects private marker/version fields in handlers. The
            // stable command path plus exact semantic comparison is the
            // managed identity for this provider.
            return (inner["command"] as? String)?.contains(marker) == true
        }
        // A stale response-schema/timeout install lacks the current version marker.
        return (inner[managedVersionKey] as? Int) == managedHookVersion
    }

    /// True when NotchDeck hooks are installed but STALE (wrong timeout/schema or
    /// duplicates) → the UI should prompt the user to reinstall.
    static func needsReinstall(_ provider: TerminalAgentProvider) -> Bool {
        let json = loadJSON(configURL(for: provider))
        guard hasMarker(in: json, provider: provider) else { return false }
        return !managedEntriesAreEquivalent(
            json,
            provider: provider,
            helper: installedHelperURL.path
        )
    }

    /// Codex 0.144.x stores reviewed hook identities in config.toml. This is
    /// intentionally conservative: absence of the PermissionRequest trust entry
    /// is definitive; presence means reviewed, while hook silence alone is never
    /// interpreted as untrusted.
    static func trustStatus(_ provider: TerminalAgentProvider) -> HookTrustStatus {
        guard provider == .codex else { return .notApplicable }
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: config) else { return .unknown }
        return codexTrustStatus(configText: text)
    }

    static func codexTrustStatus(configText: String) -> HookTrustStatus {
        guard configText.contains("[hooks.state]") else { return .approvalRequired }
        let normalized = configText.lowercased()
        return normalized.contains(":permission_request:")
            ? .reviewed
            : .approvalRequired
    }

    static func integrationState(
        provider: TerminalAgentProvider,
        installed: Bool,
        trustStatus: HookTrustStatus,
        observedEvent: Bool
    ) -> IntegrationState {
        guard installed else { return .hooksMissing }
        if observedEvent { return .working }
        guard provider == .codex else { return .working }
        return trustStatus == .reviewed ? .working : .trustRequired
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
        return try installConfiguration(
            provider: provider,
            at: configURL(for: provider),
            helper: helperURL.path
        )
    }

    static func uninstall(_ provider: TerminalAgentProvider) throws {
        _ = try uninstallConfiguration(provider: provider, at: configURL(for: provider))
    }

    @discardableResult
    static func installConfiguration(
        provider: TerminalAgentProvider,
        at url: URL,
        helper: String
    ) throws -> Plan {
        let (base, _) = try readConfiguration(at: url)
        if managedEntriesAreEquivalent(base, provider: provider, helper: helper) {
            return Plan(
                provider: provider,
                configPath: SecretSanitizer.redactHome(url.path),
                backupPath: nil,
                diff: "NotchDeck hooks are already semantically identical.",
                changed: false
            )
        }

        let merged = mergeHooks(base: base, provider: provider, helper: helper)
        let backupPath = try backup(url)
        try writeJSON(merged, to: url)
        return Plan(
            provider: provider,
            configPath: SecretSanitizer.redactHome(url.path),
            backupPath: backupPath.map(SecretSanitizer.redactHome),
            diff: "Installed \(entries(for: provider, helper: helper).count) hooks.",
            changed: true
        )
    }

    @discardableResult
    static func uninstallConfiguration(
        provider: TerminalAgentProvider,
        at url: URL
    ) throws -> Plan {
        let (_, originalData) = try readConfiguration(at: url)
        guard let originalData else {
            return Plan(
                provider: provider,
                configPath: SecretSanitizer.redactHome(url.path),
                backupPath: nil,
                diff: "No configuration file exists.",
                changed: false
            )
        }
        let edited = try removingManagedEntries(
            from: originalData,
            provider: provider
        )
        guard edited != originalData else {
            return Plan(
                provider: provider,
                configPath: SecretSanitizer.redactHome(url.path),
                backupPath: nil,
                diff: "No NotchDeck hooks were present.",
                changed: false
            )
        }
        let backupPath = try backup(url)
        do {
            try edited.write(to: url, options: .atomic)
        } catch {
            throw HookError.writeFailed(error.localizedDescription)
        }
        return Plan(
            provider: provider,
            configPath: SecretSanitizer.redactHome(url.path),
            backupPath: backupPath.map(SecretSanitizer.redactHome),
            diff: "Removed only NotchDeck-managed hook entries.",
            changed: true
        )
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
        if provider == .codex {
            removeLegacyTopLevelCodexEntries(from: &json)
        }
        var hooks = hooksDictionary(json, provider: provider) ?? [:]
        // Retire obsolete NotchDeck events too, not only events that still exist
        // in the current schema.
        for (key, value) in hooks {
            guard var array = value as? [[String: Any]] else { continue }
            array.removeAll { containsMarker($0) }
            hooks[key] = array
        }
        for spec in entries(for: provider, helper: helper) {
            let cmd = command(helper: helper, provider: provider, event: spec.event)
            // PermissionRequest must be SYNCHRONOUS: no `async`, and a timeout
            // longer than the app's 8s UI fallback so the user has time to choose.
            var hookDict: [String: Any] = ["type": "command", "command": cmd]
            if provider != .codex {
                hookDict[managedKey] = true
                hookDict[managedVersionKey] = managedHookVersion
            }
            if spec.event == .permissionRequested {
                hookDict["timeout"] = HookTimeouts.claudeHookTimeoutSeconds
            }
            var entry: [String: Any] = ["hooks": [hookDict]]
            if provider != .codex {
                entry[managedKey] = true
            }
            if spec.matcher { entry["matcher"] = "*" }
            var array = (hooks[spec.hookEvent] as? [[String: Any]]) ?? []
            array.append(entry)
            hooks[spec.hookEvent] = array
        }
        setHooksDictionary(&json, hooks, provider: provider)
        return json
    }

    static func managedEntriesAreEquivalent(
        _ json: [String: Any],
        provider: TerminalAgentProvider,
        helper: String
    ) -> Bool {
        if provider == .codex, hasLegacyTopLevelCodexMarker(in: json) {
            return false
        }
        guard let actualHooks = hooksDictionary(json, provider: provider) else { return false }
        let desiredJSON = mergeHooks(base: [:], provider: provider, helper: helper)
        guard let desiredHooks = hooksDictionary(desiredJSON, provider: provider) else { return false }

        let allKeys = Set(actualHooks.keys).union(desiredHooks.keys)
        for key in allKeys {
            let actualManaged = ((actualHooks[key] as? [[String: Any]]) ?? [])
                .filter(containsMarker)
            let desiredManaged = ((desiredHooks[key] as? [[String: Any]]) ?? [])
                .filter(containsMarker)
            guard jsonArraysEqual(actualManaged, desiredManaged) else { return false }
        }
        return true
    }

    private static func jsonArraysEqual(
        _ lhs: [[String: Any]],
        _ rhs: [[String: Any]]
    ) -> Bool {
        NSArray(array: lhs).isEqual(to: rhs)
    }

    /// Pure removal: strip every NotchDeck-added hook entry, leaving the user's.
    static func removeHooks(base: [String: Any], provider: TerminalAgentProvider) -> [String: Any] {
        var json = base
        if provider == .codex {
            removeLegacyTopLevelCodexEntries(from: &json)
        }
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
        if provider == .codex, hasLegacyTopLevelCodexMarker(in: json) {
            return true
        }
        guard let hooks = hooksDictionary(json, provider: provider) else { return false }
        return hooks.values.contains { array in
            (array as? [[String: Any]])?.contains { containsMarker($0) } ?? false
        }
    }

    private static func hasLegacyTopLevelCodexMarker(in json: [String: Any]) -> Bool {
        json.contains { key, value in
            key != "hooks"
                && ((value as? [[String: Any]])?.contains(where: containsMarker) ?? false)
        }
    }

    /// Migrate the invalid legacy layout emitted by older NotchDeck builds,
    /// where Codex event arrays were written beside `hooks` instead of inside
    /// it. Only NotchDeck entries are removed; any unrelated array entries and
    /// top-level metadata remain untouched.
    private static func removeLegacyTopLevelCodexEntries(
        from json: inout [String: Any]
    ) {
        for (key, value) in json where key != "hooks" {
            guard var entries = value as? [[String: Any]] else { continue }
            let originalCount = entries.count
            entries.removeAll(where: containsMarker)
            guard entries.count != originalCount else { continue }
            if entries.isEmpty {
                json[key] = nil
            } else {
                json[key] = entries
            }
        }
    }

    // MARK: Source-preserving uninstall

    private struct JSONSourceMember {
        var key: String
        var value: JSONSourceNode
    }

    private indirect enum JSONSourceNode {
        case object(Range<Int>, [JSONSourceMember])
        case array(Range<Int>, [JSONSourceNode])
        case string(Range<Int>)
        case scalar(Range<Int>)

        var range: Range<Int> {
            switch self {
            case .object(let range, _), .array(let range, _),
                 .string(let range), .scalar(let range):
                return range
            }
        }
    }

    private struct JSONSourceParser {
        let bytes: [UInt8]
        var index = 0

        mutating func parse() throws -> JSONSourceNode {
            skipWhitespace()
            let node = try parseValue()
            skipWhitespace()
            guard index == bytes.count else { throw syntax("trailing content") }
            return node
        }

        private mutating func parseValue() throws -> JSONSourceNode {
            skipWhitespace()
            guard index < bytes.count else { throw syntax("unexpected end of input") }
            switch bytes[index] {
            case 0x7B: return try parseObject() // {
            case 0x5B: return try parseArray()  // [
            case 0x22:
                return .string(try parseStringRange())
            default:
                return try parseScalar()
            }
        }

        private mutating func parseObject() throws -> JSONSourceNode {
            let start = index
            index += 1
            skipWhitespace()
            var members: [JSONSourceMember] = []
            if consume(0x7D) { return .object(start..<index, members) }
            while true {
                skipWhitespace()
                let keyRange = try parseStringRange()
                let keyData = Data(bytes[keyRange])
                guard let key = try JSONSerialization.jsonObject(
                    with: keyData,
                    options: .fragmentsAllowed
                ) as? String else {
                    throw syntax("invalid object key")
                }
                skipWhitespace()
                guard consume(0x3A) else { throw syntax("missing ':'") }
                let value = try parseValue()
                members.append(.init(key: key, value: value))
                skipWhitespace()
                if consume(0x7D) { break }
                guard consume(0x2C) else { throw syntax("missing ','") }
            }
            return .object(start..<index, members)
        }

        private mutating func parseArray() throws -> JSONSourceNode {
            let start = index
            index += 1
            skipWhitespace()
            var elements: [JSONSourceNode] = []
            if consume(0x5D) { return .array(start..<index, elements) }
            while true {
                elements.append(try parseValue())
                skipWhitespace()
                if consume(0x5D) { break }
                guard consume(0x2C) else { throw syntax("missing ','") }
            }
            return .array(start..<index, elements)
        }

        private mutating func parseStringRange() throws -> Range<Int> {
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw syntax("expected string")
            }
            let start = index
            index += 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    return start..<index
                }
            }
            throw syntax("unterminated string")
        }

        private mutating func parseScalar() throws -> JSONSourceNode {
            let start = index
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D:
                    guard index > start else { throw syntax("invalid value") }
                    return .scalar(start..<index)
                default:
                    index += 1
                }
            }
            guard index > start else { throw syntax("invalid value") }
            return .scalar(start..<index)
        }

        private mutating func skipWhitespace() {
            while index < bytes.count,
                  bytes[index] == 0x20 || bytes[index] == 0x09
                    || bytes[index] == 0x0A || bytes[index] == 0x0D {
                index += 1
            }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private func syntax(_ detail: String) -> HookError {
            .invalidConfig("\(detail) at byte \(index)")
        }
    }

    private static func removingManagedEntries(
        from data: Data,
        provider: TerminalAgentProvider
    ) throws -> Data {
        var parser = JSONSourceParser(bytes: Array(data))
        let root = try parser.parse()
        let hookObjects: [JSONSourceNode]
        switch provider {
        case .claudeCode:
            guard case .object(_, let rootMembers) = root,
                  let hooks = rootMembers.first(where: { $0.key == "hooks" })?.value else {
                return data
            }
            hookObjects = [hooks]
        case .codex:
            guard case .object(_, let rootMembers) = root else { return data }
            // The nested object is the supported layout. Include the root as
            // well so uninstall also cleans legacy top-level NotchDeck arrays.
            let nested = rootMembers.first(where: { $0.key == "hooks" })?.value
            hookObjects = nested.map { [$0, root] } ?? [root]
        case .unknown:
            hookObjects = [root]
        }

        var removals: [Range<Int>] = []
        for hookObject in hookObjects {
            guard case .object(_, let hookMembers) = hookObject else { continue }
            for member in hookMembers {
                guard case .array(_, let elements) = member.value, !elements.isEmpty else { continue }
                let managedIndexes = elements.indices.filter { index in
                    let range = elements[index].range
                    guard let entry = try? JSONSerialization.jsonObject(
                        with: data.subdata(in: range)
                    ) as? [String: Any] else {
                        return false
                    }
                    return containsMarker(entry)
                }
                guard !managedIndexes.isEmpty else { continue }

                var runStart = managedIndexes[0]
                var runEnd = runStart
                func appendRun(_ first: Int, _ last: Int) {
                    if first == 0, last < elements.count - 1 {
                        removals.append(
                            elements[first].range.lowerBound..<elements[last + 1].range.lowerBound
                        )
                    } else if first > 0 {
                        removals.append(
                            elements[first - 1].range.upperBound..<elements[last].range.upperBound
                        )
                    } else {
                        removals.append(
                            elements[first].range.lowerBound..<elements[last].range.upperBound
                        )
                    }
                }
                for index in managedIndexes.dropFirst() {
                    if index == runEnd + 1 {
                        runEnd = index
                    } else {
                        appendRun(runStart, runEnd)
                        runStart = index
                        runEnd = index
                    }
                }
                appendRun(runStart, runEnd)
            }
        }

        var result = data
        for range in removals.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Both providers use a top-level "hooks" document member. Codex's decoder
    /// rejects event names written directly at the document root.
    private static func hooksDictionary(_ json: [String: Any], provider: TerminalAgentProvider) -> [String: Any]? {
        switch provider {
        case .claudeCode, .codex: return json["hooks"] as? [String: Any] ?? [:]
        case .unknown: return json
        }
    }

    private static func setHooksDictionary(_ json: inout [String: Any], _ hooks: [String: Any],
                                           provider: TerminalAgentProvider) {
        switch provider {
        case .claudeCode, .codex: json["hooks"] = hooks
        case .unknown: json = hooks
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

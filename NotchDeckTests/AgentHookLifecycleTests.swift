import XCTest
import Darwin
@testable import NotchDeck

final class AgentHookLifecycleTests: XCTestCase {
    func testHelperResolutionUsesBinForCleanInstallAndPreservesReferencedLegacyPath() {
        let support = URL(fileURLWithPath: "/tmp/NotchDeck", isDirectory: true)
        let canonical = support.appendingPathComponent("bin/notchdeck-agent-hook").path
        let legacy = support.appendingPathComponent("notchdeck-agent-hook").path

        XCTAssertEqual(
            HookInstaller.resolveInstalledHelperURL(
                referencedCommands: [],
                supportDirectory: support
            ).path,
            canonical
        )
        XCTAssertEqual(
            HookInstaller.resolveInstalledHelperURL(
                referencedCommands: [
                    "\"\(legacy)\" --provider codex --event permissionRequested"
                ],
                supportDirectory: support
            ).path,
            legacy
        )
    }

    func testVersionedHelperInstallDoesNotRewriteEquivalentExecutable() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-helper-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let destination = directory.appendingPathComponent("bin/notchdeck-agent-hook")
        try Data("helper-v1".utf8).write(to: source)

        XCTAssertTrue(try HookInstaller.installHelper(
            from: source,
            to: destination,
            expectedVersion: "1.2.3-hook5",
            force: false
        ))
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: destination.path)
        let modifiedBefore = try XCTUnwrap(attributesBefore[.modificationDate] as? Date)

        XCTAssertFalse(try HookInstaller.installHelper(
            from: source,
            to: destination,
            expectedVersion: "1.2.3-hook5",
            force: false
        ))
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributesAfter[.modificationDate] as? Date, modifiedBefore)
        XCTAssertEqual(
            try String(contentsOf: HookInstaller.versionURL(for: destination)),
            "1.2.3-hook5\n"
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testVersionedHelperInstallRepairsVersionAndExecutableState() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-helper-repair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let destination = directory.appendingPathComponent("notchdeck-agent-hook")
        try Data("new-helper".utf8).write(to: source)
        try Data("old-helper".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        try Data("old-version\n".utf8).write(to: HookInstaller.versionURL(for: destination))

        XCTAssertTrue(try HookInstaller.installHelper(
            from: source,
            to: destination,
            expectedVersion: "new-version",
            force: false
        ))
        XCTAssertEqual(try String(contentsOf: destination), "new-helper")
        XCTAssertEqual(try String(contentsOf: HookInstaller.versionURL(for: destination)), "new-version\n")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    func testSemanticConfigInstallDoesNotRewriteEquivalentFile() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-config-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("hooks.json")
        let helper = "/tmp/bin/notchdeck-agent-hook"
        let thirdParty: [String: Any] = [
            "type": "command",
            "command": "/usr/local/bin/other-hook",
        ]
        let base: [String: Any] = [
            "description": "keep this metadata",
            "hooks": [
                "SessionStart": [["hooks": [thirdParty], "matcher": "third-party"]],
            ],
            "customSetting": ["enabled": true],
        ]
        let desired = HookInstaller.mergeHooks(base: base, provider: .codex, helper: helper)
        let original = try JSONSerialization.data(withJSONObject: desired, options: [])
        try original.write(to: config)
        let modifiedBefore = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: config.path)[.modificationDate] as? Date
        )

        let plan = try HookInstaller.installConfiguration(
            provider: .codex,
            at: config,
            helper: helper
        )

        XCTAssertFalse(plan.changed)
        XCTAssertNil(plan.backupPath)
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: config.path)[.modificationDate] as? Date,
            modifiedBefore
        )
    }

    func testCodexInstallMigratesLegacyTopLevelEntriesIntoHooksContainer() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-codex-shape-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("hooks.json")
        let helper = "/tmp/bin/notchdeck-agent-hook"
        let base: [String: Any] = [
            "description": "preserve me",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/opt/third-party"]],
                ]],
            ],
            "PermissionRequest": [[
                "matcher": "*",
                "notchdeckManaged": true,
                "hooks": [[
                    "type": "command",
                    "command": "\(helper) --provider codex --event permissionRequested",
                    "notchdeckManaged": true,
                ]],
            ]],
        ]
        try JSONSerialization.data(withJSONObject: base).write(to: config)

        let plan = try HookInstaller.installConfiguration(
            provider: .codex,
            at: config,
            helper: helper
        )

        XCTAssertTrue(plan.changed)
        let installed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        )
        XCTAssertEqual(installed["description"] as? String, "preserve me")
        XCTAssertNil(installed["PermissionRequest"])
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertTrue(preToolUse.contains {
            (($0["hooks"] as? [[String: Any]])?.first?["command"] as? String)
                == "/opt/third-party"
        })
        XCTAssertNotNil(hooks["PermissionRequest"])
    }

    func testCodexUninstallPreservesDocumentAndThirdPartyBytes() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-codex-remove-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("hooks.json")
        let source = """
        {
          "description": "keep",
          "hooks": {
            "PermissionRequest": [
              {"matcher":"Bash","hooks":[{"type":"command","command":"/opt/other-hook"}]},
              {"matcher":"*","notchdeckManaged":true,"hooks":[{"type":"command","command":"/tmp/notchdeck-agent-hook","notchdeckManaged":true}]}
            ]
          }
        }
        """
        let expected = """
        {
          "description": "keep",
          "hooks": {
            "PermissionRequest": [
              {"matcher":"Bash","hooks":[{"type":"command","command":"/opt/other-hook"}]}
            ]
          }
        }
        """
        try Data(source.utf8).write(to: config)

        let plan = try HookInstaller.uninstallConfiguration(provider: .codex, at: config)

        XCTAssertTrue(plan.changed)
        XCTAssertEqual(try String(contentsOf: config), expected)
    }

    func testConfigInstallMergesThirdPartyHooksThenBecomesIdempotent() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-config-merge-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("settings.json")
        let helper = "/tmp/bin/notchdeck-agent-hook"
        let originalObject: [String: Any] = [
            "theme": "user-choice",
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "third-party",
                    "hooks": [[
                        "type": "command",
                        "command": "/opt/example/approval-hook",
                    ]],
                ]],
            ],
        ]
        let original = try JSONSerialization.data(
            withJSONObject: originalObject,
            options: [.prettyPrinted]
        )
        try original.write(to: config)

        let first = try HookInstaller.installConfiguration(
            provider: .claudeCode,
            at: config,
            helper: helper
        )
        XCTAssertTrue(first.changed)
        XCTAssertNotNil(first.backupPath)
        let installedData = try Data(contentsOf: config)
        let installed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: installedData) as? [String: Any]
        )
        XCTAssertEqual(installed["theme"] as? String, "user-choice")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        let permission = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertTrue(permission.contains {
            (($0["hooks"] as? [[String: Any]])?.first?["command"] as? String)
                == "/opt/example/approval-hook"
        })

        let modifiedBefore = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: config.path)[.modificationDate] as? Date
        )
        let second = try HookInstaller.installConfiguration(
            provider: .claudeCode,
            at: config,
            helper: helper
        )
        XCTAssertFalse(second.changed)
        XCTAssertNil(second.backupPath)
        XCTAssertEqual(try Data(contentsOf: config), installedData)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: config.path)[.modificationDate] as? Date,
            modifiedBefore
        )
    }

    func testUninstallRemovesOnlyManagedEntriesAndPreservesOtherBytes() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-config-remove-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("settings.json")
        let source = """
        {
          "theme": "keep-this-format",
          "hooks": {
            "PermissionRequest": [
              {"matcher":"third","hooks":[{"type":"command","command":"/opt/other-hook"}]},
              {"matcher":"*","notchdeckManaged":true,"hooks":[{"type":"command","command":"/tmp/notchdeck-agent-hook","notchdeckManaged":true}]}
            ],
            "SessionStart": [
              {"notchdeckManaged":true,"hooks":[{"command":"/tmp/notchdeck-agent-hook"}]}
            ]
          },
          "unrelated": { "spacing" : [ 1, 2, 3 ] }
        }
        """
        let expected = """
        {
          "theme": "keep-this-format",
          "hooks": {
            "PermissionRequest": [
              {"matcher":"third","hooks":[{"type":"command","command":"/opt/other-hook"}]}
            ],
            "SessionStart": [
        __NOTCHDECK_EMPTY_ARRAY_INDENT__
            ]
          },
          "unrelated": { "spacing" : [ 1, 2, 3 ] }
        }
        """.replacingOccurrences(
            of: "__NOTCHDECK_EMPTY_ARRAY_INDENT__",
            with: "      "
        )
        try Data(source.utf8).write(to: config)

        let plan = try HookInstaller.uninstallConfiguration(provider: .claudeCode, at: config)

        XCTAssertTrue(plan.changed)
        XCTAssertNotNil(plan.backupPath)
        XCTAssertEqual(try String(contentsOf: config), expected)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(plan.backupPath))),
            source
        )
    }

    func testSocketBootstrapReplacesStaleFilesystemEntry() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-stale-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("bridge.sock").path
        try Data("stale".utf8).write(to: URL(fileURLWithPath: path))

        let lease = try BridgeSocketBootstrap.bind(path: path)
        defer { lease.closeAndUnlink() }

        var info = stat()
        XCTAssertEqual(stat(path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
        let client = Self.connectClient(path)
        XCTAssertGreaterThanOrEqual(client, 0)
        if client >= 0 { close(client) }
    }

    func testSocketBootstrapRefusesLiveListenerWithoutReplacingIt() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-live-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("bridge.sock").path
        let first = try BridgeSocketBootstrap.bind(path: path)
        defer { first.closeAndUnlink() }
        var before = stat()
        XCTAssertEqual(stat(path, &before), 0)

        XCTAssertThrowsError(try BridgeSocketBootstrap.bind(path: path)) { error in
            guard case BridgeLifecycleError.alreadyRunning(let reportedPath) = error else {
                return XCTFail("expected alreadyRunning, got \(error)")
            }
            XCTAssertEqual(reportedPath, path)
        }

        var after = stat()
        XCTAssertEqual(stat(path, &after), 0)
        XCTAssertEqual(after.st_ino, before.st_ino)
        let client = Self.connectClient(path)
        XCTAssertGreaterThanOrEqual(client, 0, "first listener must remain reachable")
        if client >= 0 { close(client) }
    }

    func testSocketBootstrapRejectsDarwinPathLimitBeforeTouchingFilesystem() {
        let path = "/" + String(repeating: "a", count: 103)
        XCTAssertEqual(path.utf8.count, 104)

        XCTAssertThrowsError(try BridgeSocketBootstrap.bind(path: path)) { error in
            guard case BridgeLifecycleError.pathTooLong(let reportedPath, let byteCount) = error else {
                return XCTFail("expected pathTooLong, got \(error)")
            }
            XCTAssertEqual(reportedPath, path)
            XCTAssertEqual(byteCount, 104)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSocketBootstrapSerializesSimultaneousLaunches() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nd-race-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("bridge.sock").path
        let queue = DispatchQueue(label: "notchdeck.socket-race", attributes: .concurrent)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var leases: [BridgeSocketLease] = []
        var alreadyRunningCount = 0
        var unexpectedErrors: [Error] = []

        for _ in 0..<2 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let lease = try BridgeSocketBootstrap.bind(path: path)
                    resultLock.lock()
                    leases.append(lease)
                    resultLock.unlock()
                } catch BridgeLifecycleError.alreadyRunning {
                    resultLock.lock()
                    alreadyRunningCount += 1
                    resultLock.unlock()
                } catch {
                    resultLock.lock()
                    unexpectedErrors.append(error)
                    resultLock.unlock()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        defer { leases.forEach { $0.closeAndUnlink() } }
        XCTAssertTrue(unexpectedErrors.isEmpty, "\(unexpectedErrors)")
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(alreadyRunningCount, 1)
    }

    private func helperURL() throws -> URL {
        try XCTUnwrap(HookInstaller.bundledHelperURL())
    }

    private func process(socketPath: String) throws -> (Process, Pipe, Pipe, Pipe) {
        let process = Process()
        process.executableURL = try helperURL()
        process.arguments = ["--provider", "codex", "--event", "permissionRequested"]
        var environment = ProcessInfo.processInfo.environment
        environment["NOTCHDECK_AGENT_HOOK_TESTING"] = "1"
        environment["NOTCHDECK_TEST_SOCKET_PATH"] = socketPath
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        return (process, input, output, error)
    }

    private func payload() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "session_id": "session-1",
            "turn_id": "turn-1",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell",
            "tool_input": ["command": "redacted"],
            "cwd": "/tmp/project",
        ])
    }

    func testMissingAppExitsPromptlyWithEmptyStdout() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchdeck-no-listener-\(UUID().uuidString).sock").path
        let (process, input, output, _) = try process(socketPath: missing)
        let started = Date()
        try process.run()
        input.fileHandleForWriting.write(try payload())
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data())
    }

    func testDecisionWritesExactProviderBytesAndExitsPromptly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchdeck-hook-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = directory.appendingPathComponent("bridge.sock").path
        let server = try makeServer(path: socketPath)
        defer { close(server); unlink(socketPath) }

        let (process, input, output, error) = try process(socketPath: socketPath)
        let started = Date()
        try process.run()
        input.fileHandleForWriting.write(try payload())
        try input.fileHandleForWriting.close()

        var descriptor = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&descriptor, 1, 2_000), 1, "helper did not connect promptly")
        let client = accept(server, nil, nil)
        XCTAssertGreaterThanOrEqual(client, 0)
        let event = try readEvent(client)
        let decision = TerminalAgentDecision(
            requestID: try XCTUnwrap(event.requestID),
            transactionID: try XCTUnwrap(event.transactionID),
            behavior: .allow
        )
        let bytes = try XCTUnwrap(TerminalAgentCodec.encodeLine(decision))
        XCTAssertEqual(bytes.withUnsafeBytes {
            write(client, $0.baseAddress, bytes.count)
        }, bytes.count)

        process.waitUntilExit()
        close(client)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(
            output.fileHandleForReading.readDataToEndOfFile(),
            CodexPermissionAdapter().response(behavior: .allow, message: nil)
        )
        XCTAssertEqual(error.fileHandleForReading.readDataToEndOfFile(), Data())
    }

    func testMalformedCodexPermissionFallsBackBeforeConnecting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchdeck-hook-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = directory.appendingPathComponent("bridge.sock").path
        let server = try makeServer(path: socketPath)
        defer { close(server); unlink(socketPath) }

        let (process, input, output, _) = try process(socketPath: socketPath)
        try process.run()
        let malformed = try JSONSerialization.data(withJSONObject: [
            "session_id": "session-1",
            "hook_event_name": "PermissionRequest",
            "tool_name": "shell",
        ])
        input.fileHandleForWriting.write(malformed)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        var descriptor = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&descriptor, 1, 0), 0)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data())
    }

    private func makeServer(path: String) throws -> Int32 {
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(server, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString {
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    $0,
                    capacity - 1
                )
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, listen(server, 1) == 0 else {
            close(server)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return server
    }

    private static func connectClient(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString {
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    $0,
                    capacity - 1
                )
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    private func readEvent(_ client: Int32) throws -> TerminalAgentEvent {
        var data = Data()
        var byte: UInt8 = 0
        while read(client, &byte, 1) == 1, byte != 0x0A {
            data.append(byte)
        }
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))
        return try XCTUnwrap(TerminalAgentCodec.decodeEvent(line))
    }
}

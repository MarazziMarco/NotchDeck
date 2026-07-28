import XCTest
import Darwin
@testable import NotchDeck

final class AgentHookLifecycleTests: XCTestCase {
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

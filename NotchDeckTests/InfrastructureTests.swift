import XCTest
@testable import NotchDeck

final class SecretSanitizerTests: XCTestCase {

    func testRedactsApiKeyAssignments() {
        let input = "running with API_KEY=sk-secret123456 and token=abcdef123456"
        let out = SecretSanitizer.redact(input)
        XCTAssertFalse(out.contains("sk-secret123456"))
        XCTAssertFalse(out.contains("abcdef123456"))
    }

    func testRedactsBearer() {
        let out = SecretSanitizer.redact("Authorization: Bearer eyJhbGciOiabcdef123")
        XCTAssertFalse(out.contains("eyJhbGciOiabcdef123"))
    }

    func testRedactsAnthropicKey() {
        let out = SecretSanitizer.redact("key is sk-ant-api03-longsecretvalue99")
        XCTAssertFalse(out.contains("sk-ant-api03-longsecretvalue99"))
    }

    func testRedactHomeCollapsesPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let out = SecretSanitizer.redactHome("\(home)/.codex/auth.json")
        XCTAssertTrue(out.hasPrefix("~/"))
    }

    func testLeavesOrdinaryTextAlone() {
        let input = "This is a normal log line with no secrets."
        XCTAssertEqual(SecretSanitizer.redact(input), input)
    }
}

final class ExecutableResolverTests: XCTestCase {

    func testResolvesFromSearchPaths() throws {
        // Create a fake executable in a temp dir and resolve it.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("faketool")
        FileManager.default.createFile(atPath: exe.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let resolver = ExecutableResolver(overridePath: nil, searchPaths: [dir.path])
        XCTAssertEqual(resolver.resolve("faketool"), exe.path)
    }

    func testOverrideWins() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("custom")
        FileManager.default.createFile(atPath: exe.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let resolver = ExecutableResolver(overridePath: exe.path, searchPaths: [])
        XCTAssertEqual(resolver.resolve("anything"), exe.path)
    }

    func testMissingReturnsNil() {
        let resolver = ExecutableResolver(overridePath: nil, searchPaths: ["/nonexistent-dir-xyz"])
        // May fall through to login shell; a clearly bogus name should still be nil.
        XCTAssertNil(resolver.resolve("definitely-not-a-real-binary-zzz-123"))
    }
}

final class PersistenceTests: XCTestCase {

    struct Sample: Codable, Equatable { var value: Int; var name: String }

    func testJSONFileStoreRoundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-\(UUID().uuidString).json")
        let store = JSONFileStore<Sample>(url: url)
        XCTAssertNil(store.load())
        let sample = Sample(value: 7, name: "hi")
        store.save(sample)
        XCTAssertEqual(store.load(), sample)
        store.delete()
        XCTAssertNil(store.load())
    }

    func testAgentSessionCodableRoundTrip() throws {
        let session = AgentSession(provider: .claudeCode, providerSessionID: "s1",
                                   title: "Refactor", projectPath: "/tmp/proj",
                                   status: .running)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)
        XCTAssertEqual(decoded, session)
    }
}

final class ExternalSessionAdapterTests: XCTestCase {

    func testAgentTitleHeuristic() {
        XCTAssertTrue(ExternalSessionAdapter.looksLikeAgent(title: "claude — myproject"))
        XCTAssertTrue(ExternalSessionAdapter.looksLikeAgent(title: "codex exec running"))
        XCTAssertFalse(ExternalSessionAdapter.looksLikeAgent(title: "vim README.md"))
    }

    func testScanEmptyWhenNotTrusted() {
        let mock = MockAccessibilityService(trusted: false)
        let adapter = ExternalSessionAdapter(accessibility: mock)
        XCTAssertTrue(adapter.scan().isEmpty)
    }
}

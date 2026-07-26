import XCTest
@testable import NotchDeck

final class CodexEventParserTests: XCTestCase {

    func testBasicSessionEvents() throws {
        let lines = try FixtureLoader.lines("codex-basic.jsonl")
        let events = lines.flatMap { CodexEventParser.parse(line: $0) }

        guard case .started(let id) = events.first else {
            return XCTFail("expected started first, got \(String(describing: events.first))")
        }
        XCTAssertEqual(id, "019f947a-94eb-7b22-b6d1-c4700317fe18")

        XCTAssertTrue(events.contains { if case .toolUse = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .message(_, let t) = $0 { return t.contains("looks good") } else { return false } })
        XCTAssertTrue(events.contains { if case .completed = $0 { return true } else { return false } })
    }

    func testApprovalDetected() throws {
        let lines = try FixtureLoader.lines("codex-approval.jsonl")
        let events = lines.flatMap { CodexEventParser.parse(line: $0) }
        XCTAssertTrue(events.contains {
            if case .approvalRequested(let s) = $0 { return s.contains("rm -rf") } else { return false }
        })
    }

    func testErrorProducesFailure() throws {
        let lines = try FixtureLoader.lines("codex-error.jsonl")
        let events = lines.flatMap { CodexEventParser.parse(line: $0) }
        XCTAssertTrue(events.contains {
            if case .failed(let r) = $0 { return r.contains("usage limit") } else { return false }
        })
    }

    func testNonJSONLineDegradesToLog() {
        let events = CodexEventParser.parse(line: "not json at all")
        XCTAssertEqual(events.count, 1)
        if case .log = events[0] {} else { XCTFail("expected log") }
    }
}

final class ClaudeEventParserTests: XCTestCase {

    func testInitAndResult() throws {
        let lines = try FixtureLoader.lines("claude-basic.jsonl")
        let events = lines.flatMap { ClaudeEventParser.parse(line: $0) }

        XCTAssertTrue(events.contains {
            if case .started(let id) = $0 { return id == "070cb7b3-7821-4c81-8417-8f1e9bd4ddb1" } else { return false }
        })
        XCTAssertTrue(events.contains {
            if case .message(_, let t) = $0 { return t == "pong" } else { return false }
        })
        XCTAssertTrue(events.contains {
            if case .completed(let s) = $0 { return s == "pong" } else { return false }
        })
    }

    func testToolUseAndErrorResult() throws {
        let lines = try FixtureLoader.lines("claude-tooluse.jsonl")
        let events = lines.flatMap { ClaudeEventParser.parse(line: $0) }
        XCTAssertTrue(events.contains {
            if case .toolUse(let n, _) = $0 { return n == "Bash" } else { return false }
        })
        XCTAssertTrue(events.contains {
            if case .failed = $0 { return true } else { return false }
        })
    }
}

final class AgentStateReducerTests: XCTestCase {

    private func session() -> AgentSession {
        AgentSession(provider: .codex, title: "t", projectPath: "/tmp", status: .starting)
    }

    func testStartedFillsProviderID() {
        let s = AgentStateReducer.reduce(session(), event: .started(providerSessionID: "abc"))
        XCTAssertEqual(s.providerSessionID, "abc")
        XCTAssertEqual(s.status, .running)
    }

    func testApprovalSetsAttention() {
        let s = AgentStateReducer.reduce(session(), event: .approvalRequested(summary: "run?"))
        XCTAssertEqual(s.status, .waitingForApproval)
        XCTAssertTrue(s.requiresAttention)
    }

    func testCompletedClearsAttention() {
        var s = AgentStateReducer.reduce(session(), event: .approvalRequested(summary: "x"))
        s = AgentStateReducer.reduce(s, event: .completed(summary: "ok"))
        XCTAssertEqual(s.status, .completed)
        XCTAssertFalse(s.requiresAttention)
        XCTAssertEqual(s.latestSummary, "ok")
    }

    func testFailedSetsFailure() {
        let s = AgentStateReducer.reduce(session(), event: .failed(reason: "boom"))
        XCTAssertEqual(s.status, .failed)
        XCTAssertTrue(s.requiresAttention)
    }

    func testAttentionRankOrdering() {
        XCTAssertLessThan(AgentSessionStatus.waitingForApproval.attentionRank,
                          AgentSessionStatus.running.attentionRank)
        XCTAssertLessThan(AgentSessionStatus.running.attentionRank,
                          AgentSessionStatus.idle.attentionRank)
    }
}

final class LineBufferTests: XCTestCase {

    func testSplitsCompleteLines() {
        var buf = LineBuffer()
        let lines = buf.append(Data("a\nb\n".utf8))
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testRetainsPartialUntilNewline() {
        var buf = LineBuffer()
        XCTAssertEqual(buf.append(Data("partial".utf8)), [])
        XCTAssertEqual(buf.append(Data(" line\n".utf8)), ["partial line"])
    }

    func testFlushReturnsTrailing() {
        var buf = LineBuffer()
        _ = buf.append(Data("x\ntrail".utf8))
        XCTAssertEqual(buf.flush(), "trail")
        XCTAssertNil(buf.flush())
    }
}

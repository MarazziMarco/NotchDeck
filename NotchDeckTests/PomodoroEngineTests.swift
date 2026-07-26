import XCTest
@testable import NotchDeck

final class PomodoroEngineTests: XCTestCase {

    private let config = PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5,
                                        longBreakMinutes: 15, sessionsBeforeLongBreak: 4)

    func testStartCountsDownFromWork() {
        var e = PomodoroEngine(config: config)
        let t0 = Date(timeIntervalSince1970: 1000)
        e.start(now: t0)
        XCTAssertEqual(e.phase, .work)
        XCTAssertEqual(e.remaining(at: t0), 25 * 60, accuracy: 0.5)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(60)), 24 * 60, accuracy: 0.5)
    }

    func testPauseFreezesRemaining() {
        var e = PomodoroEngine(config: config)
        let t0 = Date(timeIntervalSince1970: 0)
        e.start(now: t0)
        e.pause(now: t0.addingTimeInterval(120))
        // Remaining stays fixed regardless of wall-clock advancing after pause.
        let r1 = e.remaining(at: t0.addingTimeInterval(120))
        let r2 = e.remaining(at: t0.addingTimeInterval(600))
        XCTAssertEqual(r1, r2, accuracy: 0.5)
        XCTAssertEqual(r1, 23 * 60, accuracy: 0.5)
    }

    func testResumeContinues() {
        var e = PomodoroEngine(config: config)
        let t0 = Date(timeIntervalSince1970: 0)
        e.start(now: t0)
        e.pause(now: t0.addingTimeInterval(60))
        e.resume(now: t0.addingTimeInterval(600))
        // After resuming, 1 minute was already spent; 24 remain at resume instant.
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(600)), 24 * 60, accuracy: 0.5)
    }

    func testAdvanceGoesWorkToShortBreak() {
        var e = PomodoroEngine(config: config)
        let t0 = Date(timeIntervalSince1970: 0)
        e.start(now: t0)
        let finished = e.advance(now: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(finished, .work)
        XCTAssertEqual(e.phase, .shortBreak)
        XCTAssertEqual(e.completedWorkSessions, 1)
    }

    func testLongBreakAfterConfiguredSessions() {
        var e = PomodoroEngine(config: config)
        var now = Date(timeIntervalSince1970: 0)
        e.start(now: now)
        // Complete 4 work phases; the 4th should transition to a long break.
        for i in 1...4 {
            now = now.addingTimeInterval(1)
            e.advance(now: now) // finishes work -> break
            if i < 4 {
                XCTAssertEqual(e.phase, .shortBreak)
                now = now.addingTimeInterval(1)
                e.advance(now: now) // finishes break -> work
            }
        }
        XCTAssertEqual(e.phase, .longBreak)
    }

    func testRecoveryAfterElapsedWhileClosed() {
        var e = PomodoroEngine(config: config)
        let t0 = Date(timeIntervalSince1970: 0)
        e.start(now: t0)
        // Simulate reopening 26 minutes later: the work phase should have ended.
        let later = t0.addingTimeInterval(26 * 60)
        let finished = e.tickAdvancingIfComplete(now: later)
        XCTAssertEqual(finished, .work)
        XCTAssertEqual(e.phase, .shortBreak)
    }

    func testCodableRoundTrip() throws {
        var e = PomodoroEngine(config: config)
        e.start(now: Date(timeIntervalSince1970: 42))
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(PomodoroEngine.self, from: data)
        XCTAssertEqual(decoded.phase, e.phase)
        XCTAssertEqual(decoded.isRunning, e.isRunning)
    }
}

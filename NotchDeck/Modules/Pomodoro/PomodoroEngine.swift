import Foundation

enum PomodoroPhase: String, Codable, Equatable {
    case idle
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

/// Configuration for a Pomodoro cycle, in minutes.
struct PomodoroConfig: Codable, Equatable {
    var workMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLongBreak: Int = 4

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }
}

/// Pure, timestamp-driven Pomodoro engine. Uses absolute start dates so it
/// recovers correctly after sleep, relaunch or clock changes — never relies on
/// an in-memory countdown. Fully unit-testable with an injected `now`.
struct PomodoroEngine: Codable, Equatable {
    var config: PomodoroConfig
    private(set) var phase: PomodoroPhase = .idle
    /// Absolute time the current running phase started (adjusted for prior pause).
    private(set) var phaseStartedAt: Date?
    /// Seconds already elapsed before the last pause.
    private(set) var accumulatedElapsed: TimeInterval = 0
    private(set) var isRunning: Bool = false
    private(set) var completedWorkSessions: Int = 0

    init(config: PomodoroConfig = PomodoroConfig()) {
        self.config = config
    }

    /// Elapsed time in the current phase at `now`.
    func elapsed(at now: Date) -> TimeInterval {
        guard isRunning, let start = phaseStartedAt else { return accumulatedElapsed }
        return accumulatedElapsed + now.timeIntervalSince(start)
    }

    /// Remaining time (never negative) in the current phase.
    func remaining(at now: Date) -> TimeInterval {
        guard phase != .idle else { return 0 }
        return max(0, config.duration(for: phase) - elapsed(at: now))
    }

    /// Whether the current phase has elapsed at `now`.
    func isPhaseComplete(at now: Date) -> Bool {
        phase != .idle && remaining(at: now) <= 0
    }

    // MARK: Controls

    mutating func start(now: Date) {
        if phase == .idle { phase = .work }
        phaseStartedAt = now
        accumulatedElapsed = 0
        isRunning = true
    }

    mutating func pause(now: Date) {
        guard isRunning else { return }
        accumulatedElapsed = elapsed(at: now)
        isRunning = false
        phaseStartedAt = nil
    }

    mutating func resume(now: Date) {
        guard !isRunning, phase != .idle else { return }
        phaseStartedAt = now
        isRunning = true
    }

    mutating func reset() {
        phase = .idle
        phaseStartedAt = nil
        accumulatedElapsed = 0
        isRunning = false
        completedWorkSessions = 0
    }

    /// Stop the active countdown but keep accumulated statistics
    /// (`completedWorkSessions`). Used on explicit app quit so the timer does not
    /// auto-resume on next launch.
    mutating func stopKeepingStats() {
        phase = .idle
        phaseStartedAt = nil
        accumulatedElapsed = 0
        isRunning = false
    }

    /// Advance to the next phase. Returns the phase that was just completed so
    /// callers can fire a notification.
    @discardableResult
    mutating func advance(now: Date) -> PomodoroPhase {
        let finished = phase
        if phase == .work {
            completedWorkSessions += 1
            let useLong = completedWorkSessions % max(1, config.sessionsBeforeLongBreak) == 0
            phase = useLong ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        phaseStartedAt = now
        accumulatedElapsed = 0
        isRunning = true
        return finished
    }

    /// Skip current phase without counting a completed work session unless it
    /// was a work phase that already elapsed. Simplest behaviour: move on.
    mutating func skip(now: Date) {
        advance(now: now)
    }

    /// Called on a tick; if the phase completed, auto-advance and return the
    /// finished phase for notification. Otherwise nil.
    @discardableResult
    mutating func tickAdvancingIfComplete(now: Date) -> PomodoroPhase? {
        guard isRunning, isPhaseComplete(at: now) else { return nil }
        return advance(now: now)
    }
}

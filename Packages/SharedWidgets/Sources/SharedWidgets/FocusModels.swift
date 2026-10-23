import Foundation
import AppKit

public enum FocusPhase: String, Codable, Sendable {
    case idle, work, shortBreak, longBreak
    public var label: String {
        switch self {
        case .idle, .work: return "Focus"
        case .shortBreak: return "Pausa breve"
        case .longBreak: return "Pausa lunga"
        }
    }
}

public struct FocusConfig: Codable, Equatable, Sendable {
    public var workMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var sessionsBeforeLongBreak = 4
    public init() {}
    public func duration(for phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return Double(max(1, min(180, workMinutes)) * 60)
        case .shortBreak: return Double(max(1, min(60, shortBreakMinutes)) * 60)
        case .longBreak: return Double(max(1, min(120, longBreakMinutes)) * 60)
        }
    }
}

/// JSON shape also matches NotchDeck's existing PomodoroEngine.
public struct FocusEngine: Codable, Equatable, Sendable {
    public var config = FocusConfig()
    public private(set) var phase: FocusPhase = .idle
    public private(set) var phaseStartedAt: Date?
    public private(set) var accumulatedElapsed: TimeInterval = 0
    public private(set) var isRunning = false
    public private(set) var completedWorkSessions = 0
    public init() {}
    public func elapsed(at now: Date) -> TimeInterval {
        max(0, accumulatedElapsed + (isRunning ? phaseStartedAt.map { now.timeIntervalSince($0) } ?? 0 : 0))
    }
    public func remaining(at now: Date) -> TimeInterval {
        phase == .idle ? 0 : max(0, config.duration(for: phase) - elapsed(at: now))
    }
    public mutating func start(now: Date) {
        if phase == .idle { phase = .work }
        phaseStartedAt = now; accumulatedElapsed = 0; isRunning = true
    }
    public mutating func pause(now: Date) {
        guard isRunning else { return }
        accumulatedElapsed = elapsed(at: now); phaseStartedAt = nil; isRunning = false
    }
    public mutating func resume(now: Date) {
        guard !isRunning, phase != .idle else { return }
        phaseStartedAt = now; isRunning = true
    }
    public mutating func reset() { let saved = config; self = FocusEngine(); config = saved }
    @discardableResult public mutating func advance(now: Date, automatically: Bool = true) -> FocusPhase {
        let finished = phase
        if phase == .work {
            completedWorkSessions += 1
            phase = completedWorkSessions % max(1, config.sessionsBeforeLongBreak) == 0 ? .longBreak : .shortBreak
        } else { phase = .work }
        accumulatedElapsed = 0; isRunning = automatically; phaseStartedAt = automatically ? now : nil
        return finished
    }
}

public struct FocusPreferences: Codable, Equatable, Sendable {
    public var title = "Una cosa alla volta"
    public var autoAdvance = true
    public var completionSound = false
    public var color = "#F28B63"
    public init() {}
}
public struct SharedFocus: Codable, Equatable, Sendable {
    public var engine = FocusEngine()
    public var preferences = FocusPreferences()
    public var migratedLegacy = false
    public init() {}
}

@MainActor public final class SharedFocusController {
    public let channel: SharedWidgetChannel<SharedFocus>
    public var onCompletion: ((FocusPhase) -> Void)?
    private var timer: Timer?
    public init(channel: SharedWidgetChannel<SharedFocus>, ticking: Bool = true) {
        self.channel = channel
        if ticking {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }
    public func toggle(now: Date = .now) throws {
        try channel.update {
            if $0.engine.phase == .idle { $0.engine.start(now: now) }
            else if $0.engine.isRunning { $0.engine.pause(now: now) }
            else { $0.engine.resume(now: now) }
        }
    }
    public func start(now: Date = .now) throws { try channel.update { $0.engine.start(now: now) } }
    public func pause(now: Date = .now) throws { try channel.update { $0.engine.pause(now: now) } }
    public func resume(now: Date = .now) throws { try channel.update { $0.engine.resume(now: now) } }
    public func reset() throws { try channel.update { $0.engine.reset() } }
    public func skip(now: Date = .now) throws { try channel.update { $0.engine.advance(now: now) } }
    @discardableResult public func tick(now: Date = .now) -> FocusPhase? {
        channel.refresh()
        guard channel.value.engine.isRunning, channel.value.engine.remaining(at: now) <= 0 else { return nil }
        var finished: FocusPhase?
        do {
            try channel.update { state in
                guard state.engine.isRunning, state.engine.remaining(at: now) <= 0 else { return }
                finished = state.engine.advance(now: now, automatically: state.preferences.autoAdvance)
            }
            if let finished {
                if channel.value.preferences.completionSound { NSSound(named: "Glass")?.play() }
                onCompletion?(finished)
            }
        } catch { return nil }
        return finished
    }
    deinit { timer?.invalidate() }
}

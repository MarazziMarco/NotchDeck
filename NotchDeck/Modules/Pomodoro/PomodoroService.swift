import Foundation
import Combine

/// Drives `PomodoroEngine` with a wall-clock tick, persists it across launches,
/// and fires notifications when a phase completes.
@MainActor
final class PomodoroService: ObservableObject, LiveActivitySource {
    @Published private(set) var engine: PomodoroEngine
    @Published private(set) var remaining: TimeInterval = 0
    /// Briefly true right after a phase completes (for the compact "done" state).
    @Published private(set) var recentlyCompleted = false

    private var timer: Timer?
    private let store: JSONFileStore<PomodoroEngine>
    private let notifications: NotificationServing

    init(config: PomodoroConfig = PomodoroConfig(),
         notifications: NotificationServing = NotificationService(),
         fileName: String = "pomodoro.json") {
        self.store = JSONFileStore(fileName: fileName)
        self.notifications = notifications
        var restored = store.load() ?? PomodoroEngine(config: config)
        restored.config = config
        self.engine = restored
        // Recover: if it was running and the phase elapsed while we were away,
        // advance appropriately based on absolute timestamps.
        recover()
    }

    func updateConfig(_ config: PomodoroConfig) {
        engine.config = config
        persist()
    }

    private func recover() {
        let now = Date()
        // Advance through any phases that completed while the app was closed.
        var guardCount = 0
        while engine.tickAdvancingIfComplete(now: now) != nil, guardCount < 100 {
            guardCount += 1
        }
        remaining = engine.remaining(at: now)
        if engine.isRunning { startTicking() }
        persist()
    }

    /// Stop the active timer on explicit quit, preserving session stats. The
    /// timer will not auto-resume on next launch.
    func resetActiveStateForQuit() {
        stopTicking()
        engine.stopKeepingStats()
        persist()
    }

    func start() { engine.start(now: Date()); persist(); startTicking(); refresh() }
    func pause() { engine.pause(now: Date()); persist(); stopTicking(); refresh() }
    func resume() { engine.resume(now: Date()); persist(); startTicking(); refresh() }
    func reset() { engine.reset(); persist(); stopTicking(); refresh() }
    func skip() { engine.skip(now: Date()); persist(); refresh() }

    private func startTicking() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() { timer?.invalidate(); timer = nil }

    private func tick() {
        let now = Date()
        if let finished = engine.tickAdvancingIfComplete(now: now) {
            notifyPhase(finished: finished)
            flashCompleted()
            persist()
        }
        remaining = engine.remaining(at: now)
    }

    private func flashCompleted() {
        recentlyCompleted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.recentlyCompleted = false
        }
    }

    private func refresh() { remaining = engine.remaining(at: Date()) }

    private func notifyPhase(finished: PomodoroPhase) {
        let next = engine.phase
        notifications.notify(
            title: "\(finished.label) complete",
            body: "Time for \(next.label.lowercased()).")
    }

    private func persist() { store.save(engine) }

    var formattedRemaining: String {
        let total = Int(remaining.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var progress: Double {
        let duration = engine.config.duration(for: engine.phase)
        guard duration > 0 else { return 0 }
        return (duration - remaining) / duration
    }

    // MARK: LiveActivitySource

    nonisolated func currentActivity() -> ResolvedActivity? {
        MainActor.assumeIsolated {
            if recentlyCompleted && !engine.isRunning {
                return ResolvedActivity(
                    id: "pomodoro",
                    priority: .timerCompleted,
                    slot: WingSlot(symbol: "bell.fill", text: "Done", tint: .attention),
                    preferredWing: .leading,
                    attention: true,
                    tapTarget: .module("pomodoro"))
            }
            guard engine.isRunning else { return nil }
            // Combined slot (ring + MM:SS) used when another activity shares the
            // strip; split slots (ring on the left wing, MM:SS on the right)
            // when the Pomodoro is the only activity.
            let combined = WingSlot(symbol: "timer", text: formattedRemaining,
                                    progress: progress, tint: .running,
                                    monospacedDigits: true, emphasize: true)
            let ring = WingSlot(symbol: "timer", progress: progress, tint: .running)
            let time = WingSlot(text: formattedRemaining, tint: .running,
                                monospacedDigits: true, emphasize: true)
            return ResolvedActivity(
                id: "pomodoro",
                priority: .pomodoroRunning,
                slot: combined,
                preferredWing: .leading,
                tapTarget: .module("pomodoro"),
                splitLeading: ring,
                splitTrailing: time)
        }
    }
}

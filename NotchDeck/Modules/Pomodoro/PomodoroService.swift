import Foundation
import Combine
import SharedWidgets

/// Drives `PomodoroEngine` with a wall-clock tick, persists it across launches,
/// and fires notifications when a phase completes.
@MainActor
final class PomodoroService: ObservableObject, LiveActivitySource {
    @Published private(set) var engine: PomodoroEngine
    @Published private(set) var remaining: TimeInterval = 0
    /// Briefly true right after a phase completes (for the compact "done" state).
    @Published private(set) var recentlyCompleted = false

    private var sharedController: SharedFocusController?
    private var sharingObserver: AnyCancellable?
    @Published private(set) var sharingError: String?
    private var timer: Timer?
    private let store: JSONFileStore<PomodoroEngine>
    private let notifications: NotificationServing

    init(config: PomodoroConfig = PomodoroConfig(),
         notifications: NotificationServing = NotificationService(),
         fileName: String = "pomodoro.json", sharedController: SharedFocusController? = nil) {
        self.store = JSONFileStore(fileName: fileName)
        self.notifications = notifications
        var restored = store.load() ?? PomodoroEngine(config: config)
        restored.config = config
        self.engine = restored
        // Recover: if it was running and the phase elapsed while we were away,
        // advance appropriately based on absolute timestamps.
        if let shared = sharedController ?? (fileName == "pomodoro.json" ? SharedWidgetLibrary.shared.focusController : nil) {
            self.sharedController = shared
            sharingObserver = shared.channel.$value.sink { [weak self] value in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    do {
                        self.engine = try JSONDecoder().decode(PomodoroEngine.self, from: JSONEncoder().encode(value.engine))
                        self.remaining = self.engine.remaining(at: .now)
                        if self.engine.isRunning { self.startTicking() } else { self.stopTicking() }
                        self.store.save(self.engine)
                        self.sharingError = nil
                    } catch { self.sharingError = error.localizedDescription }
                }
            }
            shared.onCompletion = { [weak self] phase in
                guard let self, let finished = PomodoroPhase(rawValue: phase.rawValue) else { return }
                self.notifyPhase(finished: finished); self.flashCompleted()
            }
            shared.tick()
        } else { recover() }
    }

    func updateConfig(_ config: PomodoroConfig) {
        if let shared = sharedController {
            do {
                let value = try JSONDecoder().decode(FocusConfig.self, from: JSONEncoder().encode(config))
                try shared.channel.update { $0.engine.config = value }
            } catch { sharingError = error.localizedDescription }
            return
        }
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
        if sharedController != nil { stopTicking(); return }
        stopTicking()
        engine.stopKeepingStats()
        persist()
    }

    func start() {
        if let shared = sharedController {
            do { try shared.start(); sharingError = nil } catch { sharingError = error.localizedDescription }
            refresh(); return
        }
        engine.start(now: Date()); persist(); startTicking(); refresh() }
    func pause() {
        if let shared = sharedController {
            do { try shared.pause(); sharingError = nil } catch { sharingError = error.localizedDescription }
            refresh(); return
        }
        engine.pause(now: Date()); persist(); stopTicking(); refresh() }
    func resume() {
        if let shared = sharedController {
            do { try shared.resume(); sharingError = nil } catch { sharingError = error.localizedDescription }
            refresh(); return
        }
        engine.resume(now: Date()); persist(); startTicking(); refresh() }
    func reset() {
        if let shared = sharedController {
            do { try shared.reset(); sharingError = nil } catch { sharingError = error.localizedDescription }
            refresh(); return
        }
        engine.reset(); persist(); stopTicking(); refresh() }
    func skip() {
        if let shared = sharedController {
            do { try shared.skip(); sharingError = nil } catch { sharingError = error.localizedDescription }
            refresh(); return
        }
        engine.skip(now: Date()); persist(); refresh() }

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
        if let shared = sharedController {
            shared.tick(); remaining = engine.remaining(at: .now); return
        }
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

import Foundation
import Combine

/// Lifecycle-aware System Pulse state. It polls ONLY while its view is visible:
/// no global timer, no polling while disabled/hidden, and never a duplicate timer
/// when the view is rebuilt.
@MainActor
final class SystemPulseService: ObservableObject {
    @Published private(set) var snapshot: SystemPulseSnapshot = .empty

    private let provider: SystemMetricsProviding
    private var timer: Timer?
    /// Refresh cadence; changing it while active reschedules.
    var interval: TimeInterval = SystemPulseInterval.s15.seconds {
        didSet { if timer != nil { startTimer() } }
    }

    init(provider: SystemMetricsProviding = SystemMetricsProvider()) {
        self.provider = provider
    }

    var isPolling: Bool { timer != nil }

    /// The view appeared: refresh immediately and begin polling.
    func activate() {
        refreshNow()
        startTimer()
    }

    /// The view disappeared: stop polling (no work while invisible).
    func deactivate() { stopTimer() }

    func refreshNow() { snapshot = provider.snapshot() }

    private func startTimer() {
        stopTimer()                      // never run two timers for one view
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    deinit { timer?.invalidate() }
}

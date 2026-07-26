import AppKit
import Combine

/// A snapshot of where the pointer is relative to the notch zones.
struct PointerSnapshot: Equatable {
    var location: CGPoint
    var insideCompactActivation: Bool
    var insideExpandedPanel: Bool
    var insideAny: Bool { insideCompactActivation || insideExpandedPanel }
}

/// Dedicated, reliable pointer tracking for the notch. Does NOT rely on a view's
/// `NSTrackingArea` (which breaks when the panel frame changes or hides behind
/// the camera housing). Instead it combines global + local `NSEvent` monitors
/// for movement/drag events with a low-cost ~30 Hz safety ticker, and evaluates
/// inclusion against explicit screen-coordinate rectangles supplied by the panel
/// controller.
@MainActor
final class PointerTrackingService: ObservableObject {
    @Published private(set) var snapshot = PointerSnapshot(
        location: .zero, insideCompactActivation: false, insideExpandedPanel: false)

    /// Screen-coordinate hot zones, updated by the panel controller on every
    /// reposition / display change.
    private(set) var compactActivationRect: CGRect = .zero
    private(set) var expandedInteractionRect: CGRect = .zero

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var ticker: Timer?
    private var running = false

    var pointerLocation: CGPoint { NSEvent.mouseLocation }
    var isInsideCompactActivationArea: Bool { snapshot.insideCompactActivation }
    var isInsideExpandedPanel: Bool { snapshot.insideExpandedPanel }

    func updateRects(compact: CGRect, expanded: CGRect) {
        compactActivationRect = compact
        expandedInteractionRect = expanded
        recompute()
    }

    func start() {
        guard !running else { return }
        running = true
        let movement: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: movement) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: movement) { [weak self] event in
            self?.recompute()
            return event
        }
        // Low-cost safety ticker: catches motion when no monitor event arrives
        // (e.g. pointer parked over another app). Two rect tests per tick.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        recompute()
    }

    func stop() {
        running = false
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil; localMonitor = nil
        ticker?.invalidate(); ticker = nil
    }

    /// Pure evaluation so it can be unit-tested without event plumbing.
    nonisolated static func evaluate(location: CGPoint, compact: CGRect, expanded: CGRect) -> PointerSnapshot {
        PointerSnapshot(location: location,
                        insideCompactActivation: compact.contains(location),
                        insideExpandedPanel: expanded.contains(location))
    }

    private func recompute() {
        let next = Self.evaluate(location: NSEvent.mouseLocation,
                                 compact: compactActivationRect,
                                 expanded: expandedInteractionRect)
        if next != snapshot { snapshot = next }
    }
}

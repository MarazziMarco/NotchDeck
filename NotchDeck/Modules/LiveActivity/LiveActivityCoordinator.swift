import SwiftUI
import Combine

/// Unified coordinator shared by Utilities and Agents. Collects activities from
/// all registered sources, resolves the highest-priority compact layout, and
/// republishes it. Adding a new module's live activity means registering a
/// source here — `CompactNotchView` never changes.
@MainActor
final class LiveActivityCoordinator: ObservableObject {
    @Published private(set) var layout: LiveActivityLayout = .empty

    private var sources: [LiveActivitySource] = []
    private var cancellables = Set<AnyCancellable>()

    /// Register a source and re-resolve whenever it changes.
    func register<S: LiveActivitySource & ObservableObject>(_ source: S) {
        sources.append(source)
        source.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Recompute on the next runloop tick so the source's own state has
                // settled before we read it.
                DispatchQueue.main.async { self?.recompute() }
            }
            .store(in: &cancellables)
        recompute()
    }

    func recompute() {
        layout = Self.resolve(sources.compactMap { $0.currentActivity() })
    }

    /// Pure resolution — fully unit-testable with plain `ResolvedActivity` values.
    ///
    /// Rules:
    /// - An exclusive activity (approval/input) takes the whole strip.
    /// - Otherwise the highest-priority activity fills its preferred wing, and the
    ///   next-highest activity that prefers the OTHER wing fills that one — so a
    ///   second compatible activity can coexist.
    /// - The full compact Focus timer suppresses ordinary agent-presence counts.
    ///   Actionable Agents states remain exclusive and replace the timer.
    nonisolated static func resolve(_ activities: [ResolvedActivity]) -> LiveActivityLayout {
        let hasFocusTimer = activities.contains {
            $0.splitLeading?.progress != nil && $0.splitTrailing?.emphasize == true
        }
        let eligible = activities.filter { activity in
            guard hasFocusTimer,
                  case .activeSessions? = activity.slot.compactAgentIndicator else {
                return true
            }
            return false
        }
        let sorted = eligible.sorted { $0.priority < $1.priority }
        guard let primary = sorted.first else { return .empty }

        if primary.exclusive {
            if primary.slot.compactAgentIndicator != nil {
                return LiveActivityLayout(
                    trailing: primary.slot,
                    attention: true,
                    tapTarget: primary.tapTarget
                )
            }
            var leading = primary.slot
            leading.pulse = false
            let trailing = WingSlot(text: primary.exclusiveLabel ?? "Allow?", tint: .attention)
            return LiveActivityLayout(leading: leading, trailing: trailing,
                                      attention: true, tapTarget: primary.tapTarget)
        }

        // Sole spanning activity (e.g. a running Pomodoro with nothing else
        // active): ring on one wing, MM:SS on the other for maximum legibility.
        // With a competitor present we fall through so the other wing stays free
        // and the countdown collapses into a single wing (still readable).
        if sorted.count == 1, let l = primary.splitLeading, let t = primary.splitTrailing {
            return LiveActivityLayout(leading: l, trailing: t,
                                      attention: primary.attention, tapTarget: primary.tapTarget)
        }

        var layout = LiveActivityLayout(tapTarget: primary.tapTarget)
        var usedLeading = false
        var usedTrailing = false

        func place(_ a: ResolvedActivity) {
            switch a.preferredWing {
            case .leading where !usedLeading:
                layout.leading = a.slot; usedLeading = true
            case .trailing where !usedTrailing:
                layout.trailing = a.slot; usedTrailing = true
            case .either, .leading, .trailing:
                if !usedLeading { layout.leading = a.slot; usedLeading = true }
                else if !usedTrailing { layout.trailing = a.slot; usedTrailing = true }
            }
        }

        place(primary)
        if primary.attention { layout.attention = true }

        // Fill the remaining wing from the next distinct-wing activity.
        for a in sorted.dropFirst() {
            if usedLeading && usedTrailing { break }
            let wantsFreeWing = (a.preferredWing == .leading && !usedLeading)
                || (a.preferredWing == .trailing && !usedTrailing)
                || a.preferredWing == .either
            if wantsFreeWing {
                place(a)
                if a.attention { layout.attention = true }
            }
        }
        return layout
    }
}

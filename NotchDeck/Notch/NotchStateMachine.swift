import Foundation

/// Presentation state of the notch panel.
enum NotchPresentationState: String, Equatable, Codable {
    case compact
    case peeking
    case expanded
}

/// Which of the two faces the expanded panel is showing.
enum NotchFace: String, Equatable, Codable, CaseIterable {
    case utilities
    case agents

    var toggled: NotchFace { self == .utilities ? .agents : .utilities }
}

/// Events the notch reacts to. The machine is intentionally pure and
/// synchronous — timers and async delays live in the interaction coordinator so
/// the transition logic stays fully unit-testable.
enum NotchEvent: Equatable {
    case hoverBegan
    case hoverEnded
    case approvalPeekAvailable(Bool)
    case clicked
    case dragEntered
    case dragExited
    case escapePressed
    case outsideClicked
    case requestExpand(NotchFace?)
    case requestCompact
    case setLocked(Bool)
}

/// Deterministic notch state machine. Guarantees that a lock prevents
/// expansion and that redundant transitions are no-ops (so concurrent
/// open/close attempts cannot fight each other).
struct NotchStateMachine: Equatable {
    private(set) var presentation: NotchPresentationState = .compact
    private(set) var face: NotchFace = .utilities
    private(set) var isLocked: Bool = false
    private(set) var hasApprovalPeek: Bool = false

    /// Result of applying an event: whether anything changed, so callers can
    /// avoid re-animating identical states.
    @discardableResult
    mutating func apply(_ event: NotchEvent) -> Bool {
        let before = self
        switch event {
        case .setLocked(let locked):
            isLocked = locked
            if locked { /* keep current presentation */ }

        case .hoverBegan:
            // Hover opens Expanded through `NotchInteractionCoordinator`.
            // An empty approval Peek is never user-openable.
            break

        case .hoverEnded:
            break

        case .approvalPeekAvailable(let available):
            hasApprovalPeek = available
            if available, presentation == .compact {
                presentation = .peeking
            } else if !available, presentation == .peeking {
                presentation = .compact
            }

        case .clicked:
            guard !isLocked else { break }
            presentation = .expanded

        case .dragEntered:
            guard !isLocked else { break }
            presentation = .expanded
            face = .utilities

        case .dragExited:
            // No automatic collapse on drag exit; user may be dropping.
            break

        case .escapePressed, .outsideClicked, .requestCompact:
            presentation = hasApprovalPeek ? .peeking : .compact

        case .requestExpand(let target):
            guard !isLocked else { break }
            presentation = .expanded
            if let target { face = target }
        }
        return self != before
    }

    /// Switch faces without changing presentation.
    @discardableResult
    mutating func switchFace(to target: NotchFace? = nil) -> Bool {
        let newFace = target ?? face.toggled
        guard newFace != face else { return false }
        face = newFace
        return true
    }

    var isOpen: Bool { presentation == .expanded }
}

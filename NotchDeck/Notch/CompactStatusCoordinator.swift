import Foundation

/// The single prioritized piece of information the compact notch shows.
enum CompactStatus: Equatable {
    case normal
    case agentApproval(label: String)
    case agentInput(label: String)
    case timerFinished
    case agentFinished(label: String, failed: Bool)
    case pomodoroRunning(remaining: String)
    case dragActive
    case clipboard(symbol: String)

    var isAttention: Bool {
        switch self {
        case .agentApproval, .agentInput, .timerFinished, .agentFinished:
            return true
        default:
            return false
        }
    }
}

/// Inputs feeding the compact status decision. Deliberately plain values so the
/// resolver is fully unit-testable with no view or service dependencies.
struct CompactStatusInputs: Equatable {
    var attentionSession: AttentionInfo?
    var recentlyFinishedSession: AttentionInfo?
    var timerJustFinished: Bool = false
    var pomodoroRunningRemaining: String?
    var dragInProgress: Bool = false
    var clipboardSymbol: String?

    struct AttentionInfo: Equatable {
        var label: String
        var status: AgentSessionStatus
    }
}

/// Resolves the prioritized compact status. Priority order (spec):
/// approval > input > timer finished > agent finished/failed > pomodoro running
/// > drag > normal. No scattered conditionals in the views.
enum CompactStatusCoordinator {
    static func resolve(_ input: CompactStatusInputs) -> CompactStatus {
        if let attention = input.attentionSession {
            switch attention.status {
            case .waitingForApproval:
                return .agentApproval(label: attention.label)
            case .waitingForInput:
                return .agentInput(label: attention.label)
            default:
                break
            }
        }
        if input.timerJustFinished {
            return .timerFinished
        }
        if let finished = input.recentlyFinishedSession {
            switch finished.status {
            case .completed:
                return .agentFinished(label: finished.label, failed: false)
            case .failed:
                return .agentFinished(label: finished.label, failed: true)
            default:
                break
            }
        }
        if let remaining = input.pomodoroRunningRemaining {
            return .pomodoroRunning(remaining: remaining)
        }
        if input.dragInProgress {
            return .dragActive
        }
        if let symbol = input.clipboardSymbol {
            return .clipboard(symbol: symbol)
        }
        return .normal
    }
}

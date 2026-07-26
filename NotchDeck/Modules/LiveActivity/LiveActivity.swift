import SwiftUI
import Combine

/// Priority of a live activity for the compact notch. Lower = higher priority.
enum LiveActivityPriority: Int, Comparable, Equatable {
    case approval = 0
    case input = 1
    case timerCompleted = 2
    case pomodoroRunning = 3
    case agentsRunning = 4
    case media = 5
    case ambient = 6          // clipboard / low-signal defaults
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

/// Color role, kept out of the model so layouts stay `Equatable` and testable.
enum StatusTint: String, Equatable {
    case running, attention, approval, success, failure, idle, neutral, agentActive
    var color: Color {
        switch self {
        case .running: return DesignTokens.Palette.statusRunning
        case .attention: return DesignTokens.Palette.statusAttention
        case .approval: return DesignTokens.Palette.statusApproval
        case .success: return DesignTokens.Palette.statusSuccess
        case .failure: return DesignTokens.Palette.statusFailure
        case .idle: return DesignTokens.Palette.statusIdle
        case .neutral: return DesignTokens.Palette.secondaryText
        case .agentActive: return Color(red: 1.0, green: 0.62, blue: 0.28)  // restrained orange
        }
    }
}

/// Generic content for one physical-notch wing. Any module maps its live
/// activity to this — so `CompactNotchView` renders every module without being
/// edited when new modules are added.
struct WingSlot: Equatable {
    var symbol: String?          // SF Symbol
    var text: String?
    var progress: Double?        // 0…1 → progress ring around the symbol
    var tint: StatusTint = .neutral
    var pulse: Bool = false
    var badge: Int?              // small numeric badge (e.g. extra agents)
    var monospacedDigits: Bool = false
    /// High-contrast, non-shrinking text with a reserved minimum width (used for
    /// the Pomodoro MM:SS so the countdown is always legible).
    var emphasize: Bool = false
    /// When set, the slot renders the provider's logo/monogram instead of an SF
    /// symbol (used for the compact approval + active-agent states).
    var providerVendor: AgentVendor?
}

/// Where a compact-activity tap should expand to.
enum TapTarget: Equatable {
    case face(NotchFace)
    case module(String)
    case none
}

enum Wing: Equatable { case leading, trailing, either }

/// A resolved activity contributed by a source.
struct ResolvedActivity: Equatable {
    var id: String
    var priority: LiveActivityPriority
    var slot: WingSlot
    var preferredWing: Wing = .either
    var attention: Bool = false
    var tapTarget: TapTarget = .none
    /// Exclusive activities (approval/input) take the whole compact strip.
    var exclusive: Bool = false
    /// A short attention label shown opposite the glyph (e.g. "Allow?").
    var exclusiveLabel: String?
    /// When this is the only activity it can span both wings: `splitLeading`
    /// (e.g. a progress ring) on one side, `splitTrailing` (e.g. the MM:SS
    /// countdown) on the other. When another activity is present the layout
    /// collapses to the single combined `slot` in the preferred wing so the other
    /// wing is free.
    var splitLeading: WingSlot?
    var splitTrailing: WingSlot?
}

/// The final compact layout the notch renders.
struct LiveActivityLayout: Equatable {
    var leading: WingSlot?
    var trailing: WingSlot?
    var attention: Bool = false
    var tapTarget: TapTarget = .none

    static let empty = LiveActivityLayout()
    var isEmpty: Bool { leading == nil && trailing == nil }
}

/// Anything that can contribute a live activity (a service, agents, media…).
@MainActor
protocol LiveActivitySource: AnyObject {
    func currentActivity() -> ResolvedActivity?
}

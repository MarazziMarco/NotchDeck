import Foundation

/// Base-language (English) strings for screen capture. Centralised so the UI is
/// consistent and ready to move into a String Catalog. No mixed-language labels.
enum ScreenshotStrings {
    static let capture = "Take Screenshot"
    static let captureCompact = "Screenshot"
    static let captureAccessibility = "Capture a screenshot of your screen"
    static let record = "Record screen"
    static let stopRecording = "Stop recording"
}

/// Focus (Pomodoro) responsive layout breakpoint. At/above the threshold the
/// Focus view uses a horizontal dashboard; below it falls back to vertical.
enum FocusLayout {
    static let horizontalMinWidth: CGFloat = 620
    static func isHorizontal(availableWidth: CGFloat) -> Bool {
        availableWidth >= horizontalMinWidth
    }
}

// MARK: - Permission onboarding

/// A permission requested during first-launch setup. Only permissions the app
/// actually uses are included. Microphone is intentionally EXCLUDED — NotchDeck
/// has no microphone feature, so it must not request mic access.
enum PermissionStep: String, CaseIterable, Identifiable, Equatable {
    case welcome
    case camera            // Mirror
    case screenRecording   // Take Screenshot / recording
    case downloads         // Downloads folder access
    case terminalAutomation// Focus the exact terminal tab
    case complete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome to NotchDeck"
        case .camera: return "Camera"
        case .screenRecording: return "Screen Recording"
        case .downloads: return "Downloads Folder"
        case .terminalAutomation: return "Terminal Automation"
        case .complete: return "All set"
        }
    }
    /// Why this permission is needed (shown one at a time).
    var rationale: String {
        switch self {
        case .welcome: return "NotchDeck needs a few permissions to power its modules. You can grant them now or later in Settings."
        case .camera: return "The Mirror module shows a live camera preview. Video never leaves your Mac and is never recorded."
        case .screenRecording: return "Take Screenshot and screen recording capture your screen. macOS may ask you to enable this in System Settings and relaunch NotchDeck."
        case .downloads: return "The Downloads module shows in-progress and today's downloads. Choose your Downloads folder to grant access."
        case .terminalAutomation: return "Focus Terminal brings the exact tab where Claude or Codex is running to the front. NotchDeck only selects the existing window — it never runs commands."
        case .complete: return "You're ready to go. Re-run this setup anytime from Settings."
        }
    }
    /// Whether this step actually requests a system permission.
    var requestsPermission: Bool { self != .welcome && self != .complete }
}

/// Current state of one permission.
enum PermissionSetupState: String, Equatable {
    case notRequested
    case granted
    case denied
    case requiresSystemSettings
}

/// Pure, sequential onboarding driver. One permission at a time; never
/// re-prompts a permission the user already denied; supports Skip.
enum PermissionOnboarding {
    /// Ordered steps NotchDeck presents (microphone excluded — not used).
    static let steps: [PermissionStep] = [.welcome, .camera, .screenRecording,
                                          .downloads, .terminalAutomation, .complete]

    static func next(after step: PermissionStep) -> PermissionStep? {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return nil }
        return steps[i + 1]
    }
    static func previous(before step: PermissionStep) -> PermissionStep? {
        guard let i = steps.firstIndex(of: step), i > 0 else { return nil }
        return steps[i - 1]
    }

    /// A system prompt should be shown ONLY when the step requests a permission
    /// and it has never been requested. Denied / granted / requires-settings are
    /// never re-prompted automatically.
    static func shouldRequest(_ step: PermissionStep, state: PermissionSetupState) -> Bool {
        step.requestsPermission && state == .notRequested
    }

    /// For a denied / requires-settings permission the UI offers "Open System
    /// Settings" instead of a prompt.
    static func offersSystemSettings(_ state: PermissionSetupState) -> Bool {
        state == .denied || state == .requiresSystemSettings
    }
}

import Foundation

enum MonitorSelection: String, Codable, CaseIterable, Identifiable {
    case followMouse
    case mainDisplay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .followMouse: return "Display with pointer"
        case .mainDisplay: return "Main display"
        }
    }
}

enum FileShelfRetention: String, Codable, CaseIterable, Identifiable {
    case untilRemoved
    case untilSessionEnds
    case oneHour
    case oneDay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .untilRemoved: return "Until removed manually"
        case .untilSessionEnds: return "Until app quits"
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .untilRemoved, .untilSessionEnds: return nil
        case .oneHour: return 3600
        case .oneDay: return 86_400
        }
    }
}

/// Permission posture for managed Claude Code sessions. Never defaults to
/// bypassing permissions.
enum AgentPermissionMode: String, Codable, CaseIterable, Identifiable {
    case prompt        // default; approvals surfaced to the user
    case acceptEdits
    case plan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prompt: return "Ask for approval (safe default)"
        case .acceptEdits: return "Auto-accept edits"
        case .plan: return "Plan mode (read-only)"
        }
    }
    /// Maps to the Claude CLI `--permission-mode` value.
    var claudeFlag: String {
        switch self {
        case .prompt: return "default"
        case .acceptEdits: return "acceptEdits"
        case .plan: return "plan"
        }
    }
}

/// All persisted settings, encoded as one JSON blob in UserDefaults.
struct AppSettings: Codable, Equatable {
    // General
    var launchAtLogin: Bool = false
    var permissionsSetupCompleted: Bool = false
    /// Security-scoped bookmark to the user-chosen Downloads folder.
    var downloadsBookmark: Data? = nil
    var monitorSelection: MonitorSelection = .followMouse
    var showDockIcon: Bool = false
    var onboardingCompleted: Bool = false

    // Notch behaviour
    var hoverToOpen: Bool = true
    var openDelay: Double = 0.18
    var closeDelay: Double = 0.35
    var defaultFace: NotchFace = .utilities
    var defaultModuleID: String = "clipboard"

    // Appearance
    var reduceMotionOverride: Bool = false

    // Modules
    var moduleEnabled: [String: Bool] = [:]       // authoritative enabled state (built-in + community)
    var moduleOrder: [String] = []                // library order
    var compactIndicatorModuleIDs: [String] = ["clipboard"]
    /// Show Example/developer modules in the Modules screen.
    var showDeveloperModules: Bool = false
    /// System Pulse (community module) configuration.
    var systemPulse: SystemPulseSettings = .default
    /// Utilities → More dashboard layout (placement, order and per-module size).
    /// Independent of Home; never mixes with editorial/home fields.
    var moreLayout: MoreLayoutSettings = .init()

    // Home dashboard (nil = use per-module defaults on first run)
    var homeFavorites: [String]? = nil            // module ids shown on Home, in order
    var homeSizes: [String: ModuleDashboardSize] = [:]

    // Widget dashboard — placements persisted per layout class (grid intent, not
    // pixels). Key = NotchLayoutClass rawValue.
    var widgetPlacements: [String: [DashboardWidgetPlacement]] = [:]
    var pomodoroWidgetStyle: PomodoroWidgetStyle = .tomato

    // Appearance
    var backgroundIntensity: BackgroundIntensity = .deepBlack
    var showHomeDividers: Bool = true
    // Home Quick Note
    var noteColor: NoteColor = .yellow
    /// `nil` keeps the selected preset active. A custom value overrides only
    /// the paper colour and leaves the preset available for predictable restore.
    var noteCustomColor: NotePaperColor? = nil
    var paperStyleIntensity: PaperStyleIntensity = .medium
    var noteFontSize: NoteFontSize = .standard
    var noteShowTitle: Bool = true
    // Mirror
    var mirrorCircular: Bool = true
    var mirrorZoomed: Bool = true
    var mirrorCropLevel: MirrorCropLevel = .close
    // Editorial Home
    var homeCompositionByClass: [String: HomeCompositionStyle] = [:]   // per NotchLayoutClass
    var editorialOrder: [String]? = nil                                // custom zone order
    var editorialHidden: [String] = []                                 // hidden home modules
    var editorialWidths: [String: EditorialZoneWidth] = [:]            // semantic width per zone
    var homeLayoutPreset: HomeLayoutPreset = .balanced                 // density preset
    var homePageByClass: [String: Int] = [:]                           // current page per class
    // Files editorial tab
    var filesRightSplit: FilesRightSplit = .balanced
    var clipboardPreviewCount: Int = 3
    var filesShowSourceApp: Bool = true
    var screenShowThumbnails: Bool = true
    var filesPageByClass: [String: Int] = [:]
    var filesCompositionByClass: [String: HomeCompositionStyle] = [:]   // editorial (default) or grid
    // Module → Utilities group assignment override (empty = module default)
    var moduleGroupAssignment: [String: String] = [:]

    // Responsive layout preferences (Appearance ▸ Layout)
    var panelWidthPreference: PanelWidthPreference = .adaptive
    var dashboardDensity: DashboardDensity = .comfortable
    var tabLabelMode: TabLabelMode = .automatic
    /// nil = automatic (depends on layout class).
    var maxHomeModulesPreference: Int? = nil
    /// Last selected Utilities tab (persisted).
    var lastUtilitiesTab: String = "home"
    /// Per-module compact live-activity policy + priority.
    var moduleCompactVisibility: [String: CompactVisibilityPolicy] = [:]
    /// Follow the display containing the pointer for the notch host.
    var followActiveDisplay: Bool = true

    // Clipboard
    var clipboardMaxItems: Int = 100
    var clipboardMonitoringPaused: Bool = false
    var clipboardPrivateMode: Bool = false
    var clipboardShowCompactIndicator: Bool = true

    // File Shelf
    var fileShelfRetention: FileShelfRetention = .untilRemoved
    var fileShelfIntakeMode: FileShelfIntakeMode = .moveIntoShelf
    var fileShelfRetentionPolicy: FileShelfRetentionPolicy = .removeAfterSuccessfulDrag
    /// One-time move-mode explainer suppressed.
    var fileShelfMoveExplained: Bool = false

    // Mirror
    var mirrorPreferredCameraID: String?
    var mirrorOrientation: MirrorOrientation = .mirrored

    // Pomodoro (disabled by default per spec)
    var pomodoroEnabled: Bool = true
    var pomodoroWorkMinutes: Int = 25
    var pomodoroShortBreakMinutes: Int = 5
    var pomodoroLongBreakMinutes: Int = 15
    var pomodoroSessionsBeforeLongBreak: Int = 4

    // Agents
    var codexPathOverride: String?
    var claudePathOverride: String?
    var agentPermissionMode: AgentPermissionMode = .prompt
    var agentLoggingEnabled: Bool = true
    var agentLogMaxBytes: Int = 512 * 1024
    var externalWindowControlEnabled: Bool = false

    // Terminal integration (hook-connected sessions via the local bridge)
    var codexTerminalIntegration: Bool = false
    var claudeTerminalIntegration: Bool = false
    /// Open the notch automatically when a connected session needs approval.
    var autoOpenOnApproval: Bool = true
    var autoOpenOnInput: Bool = false

    // Agents — monitor / approval UX
    var agentPermissionHandlingMode: AgentPermissionHandlingMode = .notchWithTerminalFallback
    var terminalFallbackDelay: TerminalFallbackDelay = .s8
    /// How long a mirrored approval stays actionable in NotchDeck (default 60s).
    /// Terminal remains answerable throughout. Existing pending transactions keep
    /// the deadline assigned when they arrived; only new requests use a new value.
    var approvalAvailability: ApprovalAvailability = .default
    var recentSessionLimit: RecentSessionLimit = .ten
    var showCompletedSessions: Bool = true
    var showFailedSessions: Bool = true
    var showExternalSessions: Bool = true
    var compactAgentsDisplay: CompactAgentsDisplay = .activeCount
    var agentCompactAccent: AgentCompactAccent = .orange
    var latestMessagePreviewEnabled: Bool = true
    var agentMaxPreviewLines: Int = 2
    var completionActivitySeconds: Double = 8

    // Diagnostics
    var interactionDiagnostics: Bool = false

    var resolvedNotePaperColor: NotePaperColor {
        noteCustomColor?.clamped ?? noteColor.paperComponents
    }

    mutating func selectNotePreset(_ preset: NoteColor) {
        noteColor = preset
        noteCustomColor = nil
    }

    mutating func selectCustomNoteColor(_ colour: NotePaperColor) {
        noteCustomColor = colour.clamped
    }
}

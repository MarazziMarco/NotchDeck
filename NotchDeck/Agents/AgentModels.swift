import Foundation

enum AgentProviderKind: String, Codable, CaseIterable, Identifiable {
    case codex
    case claudeCode
    case external
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .external: return "External"
        }
    }
    var iconName: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claudeCode: return "sparkle"
        case .external: return "macwindow"
        }
    }
}

enum AgentSessionStatus: String, Codable, Equatable {
    case starting
    case idle
    case running
    case waitingForInput
    case waitingForApproval
    case completed
    case failed
    case interrupted
    case unavailable

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .idle: return "Idle"
        case .running: return "Running"
        case .waitingForInput: return "Needs input"
        case .waitingForApproval: return "Approval"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .interrupted: return "Stopped"
        case .unavailable: return "Status unavailable"
        }
    }

    /// Priority for the compact/expanded ordering. Lower sorts first.
    var attentionRank: Int {
        switch self {
        case .waitingForApproval: return 0
        case .waitingForInput: return 1
        case .running, .starting: return 2
        case .completed: return 3
        case .failed, .interrupted: return 4
        case .idle, .unavailable: return 5
        }
    }

    var requiresAttention: Bool {
        self == .waitingForApproval || self == .waitingForInput || self == .failed
    }
}

struct AgentSession: Identifiable, Codable, Equatable {
    let id: UUID
    var provider: AgentProviderKind
    var providerSessionID: String?
    var title: String
    var projectPath: String
    var status: AgentSessionStatus
    var lastActivityAt: Date
    var latestSummary: String?
    var requiresAttention: Bool
    var isManaged: Bool
    var startedAt: Date
    /// Associated external app bundle id / window, when this is an external session.
    var externalBundleID: String?
    var externalWindowTitle: String?
    /// True when a hook-connected terminal session is reporting real state via the
    /// local bridge (distinct from a plain, unintegrated external window).
    var isBridgeConnected: Bool
    /// Correlates an outstanding permission request with a bridge decision.
    var pendingApprovalRequestID: String?
    /// Explicit live approval, present ONLY for a genuine PermissionRequest.
    var approval: PendingApproval?
    /// Additional provider-native requests for this same process session. They
    /// remain isolated by request ID and are promoted in arrival order after the
    /// visible transaction leaves the helper. Optional preserves decoding of
    /// session history written before concurrent-request support existed.
    var queuedApprovals: [PendingApproval]? = nil
    var terminalTTY: String?
    var terminalAppName: String?
    var terminalBundleID: String? = nil
    var termSessionID: String? = nil
    /// Process identity for liveness / exact terminal focus.
    var pid: Int32?          // agent process
    var ppid: Int32?
    var shellPID: Int32? = nil
    /// Authoritative local process identity. PID alone is never sufficient.
    var processIdentity: AgentProcessIdentity? = nil
    var processPresence: AgentProcessPresence? = nil
    var processLastSeenAt: Date? = nil
    var processEndedAt: Date? = nil
    /// Consecutive authoritative scans that did not contain this exact
    /// PID/start-time identity. Optional preserves older persisted records.
    var processMissCount: Int? = nil
    /// Last valid controlling-terminal capture. A later nil observation does not
    /// erase it for the same process identity.
    var ttyCapture: AgentTTYCapture? = nil
    /// Terminal lifecycle — does the original tab/window still exist. Drives
    /// Active vs Recent, independently of activity/approval.
    var terminalPresence: AgentTerminalPresence = .unknown
    /// Consecutive CONFIRMED misses (successful enumerations where the TTY was
    /// absent). Query/permission/timeout errors do NOT increment this.
    var terminalMissCount: Int = 0

    /// UI-facing connectivity class.
    enum Connectivity { case connected, external, offline }
    var connectivity: Connectivity {
        if isManaged || isBridgeConnected { return .connected }
        if status == .unavailable && externalBundleID == nil { return .offline }
        return .external
    }

    init(id: UUID = UUID(),
         provider: AgentProviderKind,
         providerSessionID: String? = nil,
         title: String,
         projectPath: String,
         status: AgentSessionStatus = .starting,
         lastActivityAt: Date = Date(),
         latestSummary: String? = nil,
         requiresAttention: Bool = false,
         isManaged: Bool = true,
         startedAt: Date = Date(),
         externalBundleID: String? = nil,
         externalWindowTitle: String? = nil,
         isBridgeConnected: Bool = false,
         pendingApprovalRequestID: String? = nil,
         approval: PendingApproval? = nil,
         terminalTTY: String? = nil,
         terminalAppName: String? = nil,
         pid: Int32? = nil,
         ppid: Int32? = nil) {
        self.id = id
        self.provider = provider
        self.providerSessionID = providerSessionID
        self.title = title
        self.projectPath = projectPath
        self.status = status
        self.lastActivityAt = lastActivityAt
        self.latestSummary = latestSummary
        self.requiresAttention = requiresAttention
        self.isManaged = isManaged
        self.startedAt = startedAt
        self.externalBundleID = externalBundleID
        self.externalWindowTitle = externalWindowTitle
        self.isBridgeConnected = isBridgeConnected
        self.pendingApprovalRequestID = pendingApprovalRequestID
        self.approval = approval
        self.terminalTTY = terminalTTY
        self.terminalAppName = terminalAppName
        self.pid = pid
        self.ppid = ppid
    }

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    /// Resolved provider vendor (sniffs external window titles / summaries).
    var vendor: AgentVendor {
        let hint = [title, externalWindowTitle, latestSummary].compactMap { $0 }.joined(separator: " ")
        return AgentVendor.resolve(kind: provider, hint: hint.isEmpty ? nil : hint)
    }
    var appearance: AgentProviderAppearance {
        AgentProviderAppearanceRegistry.appearance(vendor)
    }
    /// True only for a live, functional pending approval.
    var hasLiveApproval: Bool { approval?.isLive == true }
    var queuedApprovalCount: Int { queuedApprovals?.count ?? 0 }
}

/// Availability of a provider's CLI.
struct ProviderAvailability: Equatable {
    var isInstalled: Bool
    var executablePath: String?
    var version: String?
    var authenticated: Bool?     // nil = unknown / not detectable without exposing secrets
    var detail: String?

    static let notInstalled = ProviderAvailability(isInstalled: false, executablePath: nil,
                                                   version: nil, authenticated: nil, detail: nil)
}

/// Options for launching a managed session.
struct AgentLaunchConfiguration: Equatable {
    var permissionMode: AgentPermissionMode = .prompt
    var model: String?
    var extraEnvironment: [String: String] = [:]
}

/// Normalized event emitted by a provider adapter as a session progresses.
enum AgentEvent: Equatable {
    case started(providerSessionID: String?)
    case status(AgentSessionStatus)
    case message(role: String, text: String)
    case approvalRequested(summary: String)
    case toolUse(name: String, summary: String)
    case completed(summary: String?)
    case failed(reason: String)
    case log(String)
}

import AppKit
import AVFoundation
import CoreGraphics

/// Drives the first-launch Permissions Setup window. One permission at a time,
/// live status, never re-prompts a denied permission. Microphone is intentionally
/// absent (no feature needs it).
@MainActor
final class PermissionsSetupModel: ObservableObject {
    @Published var step: PermissionStep = .camera
    @Published private(set) var states: [PermissionStep: PermissionSetupState] = [:]
    @Published private(set) var busy = false

    private let settings: SettingsStore
    private let camera = CameraPermissionService()
    private let terminal = TerminalController()

    init(settings: SettingsStore) {
        self.settings = settings
        step = PermissionOnboarding.steps.first { $0.requestsPermission } ?? .camera
        refreshAll()
    }

    // MARK: Status

    func refreshAll() {
        for s in PermissionOnboarding.steps where s.requestsPermission {
            states[s] = liveState(s)
        }
    }

    func state(_ s: PermissionStep) -> PermissionSetupState { states[s] ?? .notRequested }

    private func liveState(_ s: PermissionStep) -> PermissionSetupState {
        switch s {
        case .camera:
            switch camera.status {
            case .granted: return .granted
            case .denied: return .denied
            case .restricted: return .requiresSystemSettings
            case .notDetermined: return .notRequested
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notRequested
        case .downloads:
            return settings.settings.downloadsBookmark != nil ? .granted : .notRequested
        case .terminalAutomation:
            switch terminal.enumerate() {
            case .success: return .granted
            case .queryError: return .denied            // Automation not authorised
            case .terminalNotRunning: return .notRequested
            }
        default:
            return .notRequested
        }
    }

    // MARK: Requests (sequential — one system prompt at a time)

    func request(_ s: PermissionStep) {
        guard !busy else { return }
        guard PermissionOnboarding.shouldRequest(s, state: state(s)) else { return }
        busy = true
        Task {
            let result = await performRequest(s)
            await MainActor.run {
                self.states[s] = result
                self.busy = false
            }
        }
    }

    private func performRequest(_ s: PermissionStep) async -> PermissionSetupState {
        switch s {
        case .camera:
            let r = await camera.request()
            return r == .granted ? .granted : .denied
        case .screenRecording:
            // Triggers the system prompt; the user usually must enable it in
            // System Settings and relaunch, so we report requires-settings if it
            // did not immediately flip to granted.
            let ok = CGRequestScreenCaptureAccess()
            return ok || CGPreflightScreenCaptureAccess() ? .granted : .requiresSystemSettings
        case .downloads:
            return chooseDownloadsFolder() ? .granted : .notRequested
        case .terminalAutomation:
            // A harmless existing-tab enumeration triggers/verifies Automation
            // consent. It never opens a window or runs a command.
            switch terminal.enumerate() {
            case .success: return .granted
            case .queryError: return .denied
            case .terminalNotRunning: return .notRequested
            }
        default:
            return .notRequested
        }
    }

    /// Real folder selection; persists a security-scoped bookmark.
    @discardableResult
    private func chooseDownloadsFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Grant Access"
        panel.message = "Choose your Downloads folder"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.settings.downloadsBookmark = data
            return true
        }
        return false
    }

    // MARK: Navigation

    func skip() { advance() }
    func advanceAfterRequest() { advance() }

    private func advance() {
        if let next = PermissionOnboarding.next(after: step) {
            step = next
        } else {
            step = .complete
        }
    }

    var isComplete: Bool { step == .complete }

    func openSystemSettings(for s: PermissionStep) {
        let anchor: String
        switch s {
        case .camera: anchor = "Privacy_Camera"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .terminalAutomation: anchor = "Privacy_Automation"
        default: anchor = "Privacy"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func finish() {
        settings.settings.permissionsSetupCompleted = true
    }
}

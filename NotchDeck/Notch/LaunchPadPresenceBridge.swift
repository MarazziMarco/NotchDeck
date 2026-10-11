import AppKit
import ActionKit

/// Bridges ActionKit's `LaunchPadPresenceObserver` (LaunchPad's distributed
/// show/hide notifications, schema §10) with the AppKit termination hook the
/// Foundation-only observer deliberately leaves to the host app:
/// `NSWorkspace.didTerminateApplicationNotification` for LaunchPad's bundle
/// id, so a crash or `kill -9` still resumes NotchDeck even when `didHide`
/// never posts.
///
/// `onChange` fires on the main actor exactly when `isSuspended` actually
/// flips: `.shown` → suspended; `.hidden` and termination → resumed.
/// Duplicate/no-op events are absorbed by `PresenceState` inside the
/// observer, so callers never see a redundant call.
@MainActor
final class LaunchPadPresenceBridge {
    /// Passthrough so call sites (including tests) never need `import
    /// ActionKit` just to post/observe LaunchPad's two notifications.
    static let didShow = LaunchPadPresence.didShow
    static let didHide = LaunchPadPresence.didHide

    private(set) var isSuspended = false
    private var observer: LaunchPadPresenceObserver?
    private var terminationToken: NSObjectProtocol?
    private let workspaceCenter: NotificationCenter
    private let bundleId: String
    private let onChange: (Bool) -> Void

    /// - Parameter bundleId: the bundle id a termination notification must
    ///   carry to resume us. Defaults to LaunchPad's real bundle id;
    ///   injectable so a test can exercise this path against
    ///   `NSRunningApplication.current` (the only `NSRunningApplication` a
    ///   test can get a handle on — it has no public initializer).
    init(
        center: PresenceNotificationCenter = DistributedNotificationCenter.default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        bundleId: String = LaunchPadPresence.bundleId,
        onChange: @escaping (Bool) -> Void
    ) {
        self.workspaceCenter = workspaceCenter
        self.bundleId = bundleId
        self.onChange = onChange
        observer = LaunchPadPresenceObserver(center: center) { [weak self] suspended in
            self?.apply(suspended)
        }
        terminationToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self, Self.terminatedBundleId(from: note) == self.bundleId else { return }
            Task { @MainActor [weak self] in
                self?.observer?.providerTerminated()
            }
        }
    }

    /// Pulled out as a pure, testable function: `NSRunningApplication` has no
    /// public initializer, so a real termination notification can't be
    /// constructed in a test, but the bundle-id extraction it's matched
    /// against can be exercised directly.
    static func terminatedBundleId(from note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    /// Stops observing both the distributed presence notifications and the
    /// workspace termination hook. Safe to call more than once.
    func invalidate() {
        if let t = terminationToken {
            workspaceCenter.removeObserver(t)
            terminationToken = nil
        }
        observer = nil
    }

    private func apply(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        onChange(suspended)
    }

    deinit {
        // Not main-actor: deinit can't hop isolation (same constraint
        // ActionKit's own `LaunchPadPresenceObserver.deinit` documents).
        // Removing a `NotificationCenter` token touches no actor-isolated
        // state, so it's safe directly here; `observer`'s own deinit (run by
        // ARC as this instance is torn down) removes its tokens the same way.
        if let t = terminationToken {
            workspaceCenter.removeObserver(t)
        }
    }
}

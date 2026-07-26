import AppKit
import ApplicationServices

/// A window discovered via the Accessibility API.
struct ExternalWindowInfo: Identifiable, Equatable {
    var id: String { "\(pid)-\(windowNumber)-\(title)" }
    var pid: pid_t
    var bundleID: String?
    var appName: String
    var title: String
    var windowNumber: Int
    var isMinimized: Bool
    var frame: CGRect
}

/// Contract for external-window control so it can be mocked in tests.
protocol AccessibilityControlling {
    var isTrusted: Bool { get }
    func requestPermission()
    func runningAgentCandidateApps() -> [NSRunningApplication]
    func windows(for app: NSRunningApplication) -> [ExternalWindowInfo]
    func raise(_ window: ExternalWindowInfo) -> Bool
    func activateApp(pid: pid_t) -> Bool
}

/// Real implementation backed by AXUIElement. Never reads screen pixels, never
/// injects keystrokes — only enumerates accessible windows and raises them.
struct AccessibilityService: AccessibilityControlling {

    /// Bundle identifiers of terminals / editors likely to host agent sessions.
    static let candidateBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.github.atom",
        "co.zeit.hyper",
    ]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func runningAgentCandidateApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bid = app.bundleIdentifier else { return false }
            return Self.candidateBundleIDs.contains(bid)
        }
    }

    func windows(for app: NSRunningApplication) -> [ExternalWindowInfo] {
        guard isTrusted else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }

        return windows.enumerated().compactMap { index, window in
            let title = stringAttribute(window, kAXTitleAttribute) ?? "Untitled"
            let minimized = boolAttribute(window, kAXMinimizedAttribute) ?? false
            let frame = frameAttribute(window)
            return ExternalWindowInfo(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                appName: app.localizedName ?? "App",
                title: title,
                windowNumber: index,
                isMinimized: minimized,
                frame: frame)
        }
    }

    func raise(_ window: ExternalWindowInfo) -> Bool {
        guard isTrusted else { return false }
        let appElement = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              window.windowNumber < windows.count else {
            return activateApp(pid: window.pid)
        }
        let target = windows[window.windowNumber]
        // Un-minimize if needed, then raise.
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let raised = AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success
        _ = activateApp(pid: window.pid)
        return raised
    }

    func activateApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [])
    }

    // MARK: AX helpers

    private func stringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return (value as? Bool)
    }

    private func frameAttribute(_ element: AXUIElement) -> CGRect {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var frame = CGRect.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           let posValue {
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            frame.origin = point
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue {
            var size = CGSize.zero
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            frame.size = size
        }
        return frame
    }
}

import AppKit

/// Turns accessible external windows into read-only `AgentSession` records.
/// We never claim to know an external session's internal state from its window
/// title — such sessions are marked `.unavailable` ("Status unavailable").
struct ExternalSessionAdapter {
    let accessibility: AccessibilityControlling

    init(accessibility: AccessibilityControlling = AccessibilityService()) {
        self.accessibility = accessibility
    }

    /// Heuristic: does a window title look like it hosts a coding agent?
    static func looksLikeAgent(title: String) -> Bool {
        let lower = title.lowercased()
        let needles = ["codex", "claude", "claude code", "agent", "aider"]
        return needles.contains { lower.contains($0) }
    }

    /// Scan candidate apps and produce external session records for likely
    /// agent windows. Includes non-matching windows only when the app is a
    /// terminal (so users can manually associate them).
    func scan() -> [AgentSession] {
        guard accessibility.isTrusted else { return [] }
        var results: [AgentSession] = []
        for app in accessibility.runningAgentCandidateApps() {
            for window in accessibility.windows(for: app) where !window.title.isEmpty {
                let likely = Self.looksLikeAgent(title: window.title)
                guard likely else { continue }
                let session = AgentSession(
                    provider: .external,
                    providerSessionID: nil,
                    title: window.title,
                    projectPath: "",
                    status: .unavailable,
                    latestSummary: "External window in \(window.appName)",
                    requiresAttention: false,
                    isManaged: false,
                    externalBundleID: window.bundleID,
                    externalWindowTitle: window.title)
                results.append(session)
            }
        }
        return results
    }

    /// Raise the external window backing a session.
    @discardableResult
    func focus(_ session: AgentSession) -> Bool {
        guard let bundleID = session.externalBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return false }
        let windows = accessibility.windows(for: app)
        if let match = windows.first(where: { $0.title == session.externalWindowTitle }) {
            return accessibility.raise(match)
        }
        return accessibility.activateApp(pid: app.processIdentifier)
    }
}

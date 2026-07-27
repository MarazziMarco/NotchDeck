import Foundation

/// Authoritative metadata + enablement for the Agents workspace as a built-in
/// module. Agents is a TOP-LEVEL WORKSPACE (shown beside Utilities), never a
/// Home card or a Utilities tab, so it declares the `.workspace` surface and is
/// deliberately absent from `ModuleRegistry.allModules`.
///
/// There is ONE enablement state: `AppSettings.moduleEnabled["built-in.agents"]`
/// (defaulting to `true`). The Modules screen is its only authoritative writer.
enum AgentsModule {
    static let identifier = "built-in.agents"

    /// Default-enabled so existing users and new installs keep the current
    /// Agents behaviour until they explicitly disable it in Settings → Modules.
    static let descriptor = ModuleDescriptor(
        identifier: identifier,
        displayName: AgentsModuleStrings.displayName,
        summary: AgentsModuleStrings.summary,
        version: "1.0.0",
        author: "NotchDeck",
        category: .developerTools,
        iconSystemName: "cpu",
        defaultEnabled: true,
        surfaces: [.workspace, .compactLiveActivity, .settingsSection, .backgroundService],
        capabilities: [.terminalSessionEvents, .agentApprovalEvents, .terminalAutomation],
        hasSettings: true)

    /// Single source of truth for whether the Agents workspace is enabled.
    static func isEnabled(_ settings: AppSettings) -> Bool {
        ModuleEnablement.isEnabled(identifier, defaultEnabled: descriptor.defaultEnabled, settings: settings)
    }
}

/// Localization-ready strings for the Agents module (visible app stays English).
/// Kept in one place so no view hard-codes them.
enum AgentsModuleStrings {
    static let displayName = NSLocalizedString(
        "agents.module.name", value: "Agents", comment: "Agents workspace module name")
    static let summary = NSLocalizedString(
        "agents.module.summary",
        value: "Monitor Claude Code and Codex sessions, handle permission requests and return to the corresponding terminal.",
        comment: "Agents module one-line description")
    static let hookExplanation = NSLocalizedString(
        "agents.module.hookExplanation",
        value: "Disabling Agents hides the workspace and stops NotchDeck monitoring. Installed Claude Code and Codex hooks are not removed.",
        comment: "Explains that disabling Agents does not uninstall hooks")
    static let manageIntegration = NSLocalizedString(
        "agents.module.manageIntegration", value: "Manage Agent Integration",
        comment: "Opens the existing Agents integration settings")
}

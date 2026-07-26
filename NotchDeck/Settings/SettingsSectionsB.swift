import SwiftUI
import AppKit

struct AgentsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var coordinator: AgentCoordinator

    var body: some View {
        SettingsGroup(title: "Providers") {
            providerRow(.codex, override: $settings.settings.codexPathOverride)
            Divider()
            providerRow(.claudeCode, override: $settings.settings.claudePathOverride)
            Button("Re-check providers") {
                Task { await coordinator.refreshAvailability() }
            }
        }
        SettingsGroup(title: "Approvals") {
            Picker("Permission handling", selection: $settings.settings.agentPermissionHandlingMode) {
                ForEach(AgentPermissionHandlingMode.allCases) { Text($0.label).tag($0) }
            }
            if settings.settings.agentPermissionHandlingMode == .notchWithTerminalFallback {
                Picker("Terminal fallback delay", selection: $settings.settings.terminalFallbackDelay) {
                    ForEach(TerminalFallbackDelay.allCases) { Text($0.label).tag($0) }
                }
            }
            Text("NotchDeck answers a permission request, hands off to the native terminal prompt, or NotchDeck-first with terminal fallback. It never simulates keystrokes and never auto-approves. These are sequential options, not simultaneous dual approval.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Open the notch when an agent needs approval", isOn: $settings.settings.autoOpenOnApproval)
            Toggle("Open the notch when an agent needs input", isOn: $settings.settings.autoOpenOnInput)
        }
        SettingsGroup(title: "Sessions") {
            Picker("Recent session limit", selection: $settings.settings.recentSessionLimit) {
                ForEach(RecentSessionLimit.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Show completed sessions", isOn: $settings.settings.showCompletedSessions)
            Toggle("Show failed sessions", isOn: $settings.settings.showFailedSessions)
            Toggle("Show external sessions", isOn: $settings.settings.showExternalSessions)
            Toggle("Latest-message preview", isOn: $settings.settings.latestMessagePreviewEnabled)
            Picker("Maximum preview lines", selection: $settings.settings.agentMaxPreviewLines) {
                ForEach([1, 2, 3], id: \.self) { Text("\($0)").tag($0) }
            }
        }
        SettingsGroup(title: "Compact live activity") {
            Picker("Compact Agents display", selection: $settings.settings.compactAgentsDisplay) {
                ForEach(CompactAgentsDisplay.allCases) { Text($0.label).tag($0) }
            }
            Picker("Compact accent", selection: $settings.settings.agentCompactAccent) {
                ForEach(AgentCompactAccent.allCases) { Text($0.label).tag($0) }
            }
        }
        SettingsGroup(title: "Behaviour") {
            Picker("Managed permission mode", selection: $settings.settings.agentPermissionMode) {
                ForEach(AgentPermissionMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Keep a rotating diagnostic log per session", isOn: $settings.settings.agentLoggingEnabled)
            Toggle("Control external agent windows (Accessibility)",
                   isOn: $settings.settings.externalWindowControlEnabled)
            Text("Managed sessions reuse the CLI's own authentication. NotchDeck never stores API keys.")
                .font(.caption).foregroundStyle(.secondary)
        }
        TerminalIntegrationView()
    }

    @ViewBuilder private func providerRow(_ kind: AgentProviderKind, override: Binding<String?>) -> some View {
        let availability = coordinator.availability[kind]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: kind.iconName)
                Text(kind.displayName).fontWeight(.medium)
                Spacer()
                statusTag(availability)
            }
            if let a = availability, a.isInstalled {
                Text(a.version ?? "version unknown").font(.caption).foregroundStyle(.secondary)
                Text(SecretSanitizer.redactHome(a.executablePath ?? "")).font(.caption2)
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Choose binary…") { chooseBinary(override) }
                if override.wrappedValue != nil {
                    Button("Clear") { override.wrappedValue = nil }
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private func statusTag(_ a: ProviderAvailability?) -> some View {
        if let a, a.isInstalled {
            let authed = a.authenticated == true
            Text(authed ? "Ready" : "Sign-in needed")
                .font(.caption).foregroundStyle(authed ? .green : .orange)
        } else {
            Text("Not installed").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseBinary(_ binding: Binding<String?>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
            Task { await coordinator.refreshAvailability() }
        }
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject private var permissions: PermissionCoordinator
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        SettingsGroup(title: "Setup") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions Setup").fontWeight(.medium)
                    Text("Re-run the guided setup for Camera, Screen Recording, Downloads and Terminal Automation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Setup…") { PermissionsSetupWindow.shared.show(environment: env) }
            }
        }
        SettingsGroup(title: "Permissions") {
            ForEach(AppPermission.allCases) { permission in
                permissionRow(permission)
                Divider()
            }
            HStack {
                Text("Login Item")
                Spacer()
                Text(LoginItemService.isEnabled ? "Enabled" : "Disabled")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await permissions.refresh() }
    }

    @ViewBuilder private func permissionRow(_ permission: AppPermission) -> some View {
        let status = permissions.status(for: permission)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(permission.title).fontWeight(.medium)
                Spacer()
                Text(statusLabel(status)).font(.caption)
                    .foregroundStyle(status.isGranted ? .green : .secondary)
            }
            Text(permission.explanation).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(status.isGranted ? "Granted" : "Request") {
                    Task { await permissions.request(permission) }
                }.disabled(status.isGranted)
                Button("Open System Settings") { permissions.openSystemSettings(for: permission) }
            }
            .controlSize(.small)
        }
    }

    private func statusLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not set"
        }
    }
}

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var agentStore: AgentSessionStore
    @EnvironmentObject private var diagnostics: NotchDiagnostics

    var body: some View {
        SettingsGroup(title: "Diagnostics") {
            Toggle("Show Dock icon (development)", isOn: Binding(
                get: { settings.settings.showDockIcon },
                set: {
                    settings.settings.showDockIcon = $0
                    NSApp.setActivationPolicy($0 ? .regular : .accessory)
                }))
            Toggle("Interaction diagnostics overlay", isOn: Binding(
                get: { settings.settings.interactionDiagnostics },
                set: {
                    settings.settings.interactionDiagnostics = $0
                    diagnostics.enabled = $0
                }))
            Text("Shows the compact/expanded hit rects, pointer position, state machine and the last open/close reason on the notch. Off by default.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open logs folder") {
                NSWorkspace.shared.open(AppPaths.logsDirectory)
            }
            Text("Managed sessions: \(agentStore.sessions.filter { $0.isManaged }.count) · External: \(agentStore.sessions.filter { !$0.isManaged }.count)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Logs are sanitized of API keys, tokens and credentials before being written.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        SettingsGroup(title: "About NotchDeck") {
            Text("NotchDeck").font(.title2).fontWeight(.semibold)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                .foregroundStyle(.secondary)
            Text("A native macOS surface around the notch: utilities and coding-agent control. Everything stays local — no telemetry, no account, no cloud.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

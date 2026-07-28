import SwiftUI

/// Settings › Coding Agents › Terminal Integration. Explicit, reversible install
/// of local hooks so normal terminal sessions (codex / claude) become
/// "Connected" in the Agents dashboard, with Allow/Deny surfaced in the notch.
/// Shows detailed, specific diagnostics instead of a vague Offline state.
struct TerminalIntegrationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var stats: TerminalBridgeStats

    @State private var message: String?
    @State private var previewText: String?
    @State private var previewProvider: TerminalAgentProvider = .codex
    @State private var selfTest: SelfTestResult?
    @State private var testing = false

    private var hookLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchDeck/agent-hook.log")
    }

    var body: some View {
        SettingsGroup(title: "Terminal Integration") {
            Text("Connect normally-launched Codex / Claude Code terminal sessions so NotchDeck shows their real status and approval requests. Hooks are installed with your explicit consent, backed up first, and fully removable.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            providerBlock("Codex CLI", provider: .codex,
                          binding: $settings.settings.codexTerminalIntegration)
            Divider()
            providerBlock("Claude Code", provider: .claudeCode,
                          binding: $settings.settings.claudeTerminalIntegration)

            Divider()
            bridgeStatus
            Divider()
            selfTestSection
            Divider()
            countersSection
            Divider()
            logSection

            Toggle("Open the notch automatically on approval requests",
                   isOn: $settings.settings.autoOpenOnApproval)

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Sessions started before installing hooks may stay External — restart or resume the agent afterwards. Codex hooks must be reviewed/trusted with `/hooks` in the Codex CLI; use `/hooks` in Claude Code to inspect loaded events. NotchDeck never auto-approves, never simulates keystrokes, and never stores prompts.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: Binding(get: { previewText.map { PreviewBox(text: $0) } },
                             set: { previewText = $0?.text })) { box in
            VStack(alignment: .leading, spacing: 10) {
                Text("Hook configuration preview").font(.headline)
                ScrollView { Text(box.text).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Spacer()
                    Button("Close") { previewText = nil }
                    Button("Install") { install(previewProvider); previewText = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 560, height: 420)
        }
    }

    private struct PreviewBox: Identifiable { let id = UUID(); let text: String }

    @ViewBuilder private func providerBlock(_ title: String, provider: TerminalAgentProvider,
                                            binding: Binding<Bool>) -> some View {
        let installed = HookInstaller.isInstalled(provider)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { binding.wrappedValue },
                    set: { on in
                        binding.wrappedValue = on
                        if on { install(provider) } else { uninstall(provider) }
                    }))
                    .labelsHidden()
            }

            ForEach(HookInstaller.validate(provider, socketExists: stats.isListening)) { check in
                HStack(spacing: 6) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(check.ok ? Color.green : Color.orange).font(.system(size: 10))
                    Text(check.name).font(.caption).frame(width: 110, alignment: .leading)
                    Text(check.detail).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            if installed && HookInstaller.needsReinstall(provider) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.orange).font(.system(size: 11))
                    Text("Installed hooks are outdated. Reinstall Hooks to apply the corrected permission-response format.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if installed && provider == .codex
                && HookInstaller.trustStatus(.codex) == .approvalRequired {
                Label("Codex hook approval required", systemImage: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.statusAttention)
            }

            HStack(spacing: 8) {
                Button("Preview") { preview(provider) }
                Button("Open config") { HookInstaller.openConfigFile(provider) }
                Button("Copy report") { copyReport(provider) }
                Button(installed ? "Reinstall Hooks" : "Install") { install(provider) }
                Button("Uninstall") { uninstall(provider) }.disabled(!installed)
                #if DEBUG
                Button("Copy Diagnostics") { copyDiagnostics() }
                #endif
            }
            .controlSize(.small)
        }
    }

    private var bridgeStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(stats.isListening ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(stats.isListening ? "Bridge socket active" : "Bridge socket not listening")
                    .font(.caption).fontWeight(.medium)
            }
            Text("Events received: \(stats.decodedEvents)   ·   Last: \(stats.lastEventDescription)")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Last connected session: \(stats.lastConnectedTitle)")
                .font(.caption2).foregroundStyle(.secondary)
            if let lifecycleError = stats.lastLifecycleError {
                Text(lifecycleError)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.statusAttention)
                    .textSelection(.enabled)
            }
        }
    }

    private func preview(_ provider: TerminalAgentProvider) {
        do {
            previewProvider = provider
            previewText = try HookInstaller.preview(provider)
        } catch { message = error.localizedDescription }
    }

    private func install(_ provider: TerminalAgentProvider) {
        do {
            let plan = try HookInstaller.install(provider)
            message = "Installed. Backup: \(plan.backupPath ?? "none (new file)"). Restart your terminal sessions to connect."
        } catch {
            message = error.localizedDescription
            if provider == .codex { settings.settings.codexTerminalIntegration = false }
            else { settings.settings.claudeTerminalIntegration = false }
        }
    }

    private func uninstall(_ provider: TerminalAgentProvider) {
        do {
            try HookInstaller.uninstall(provider)
            message = "Hooks removed for \(provider.rawValue)."
        } catch { message = error.localizedDescription }
    }

    #if DEBUG
    private func copyDiagnostics() {
        let text = AgentApprovalDiagnostics.shared.snapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "No approval/terminal transactions recorded yet." : text,
                                       forType: .string)
        message = "Approval diagnostics copied to clipboard."
    }
    #endif

    private func copyReport(_ provider: TerminalAgentProvider) {
        let report = HookInstaller.diagnosticReport(provider, socketExists: stats.isListening)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        message = "Diagnostic report copied to clipboard."
    }

    // MARK: Self-test

    private var selfTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Run Bridge Self-Test") { runSelfTest(.codex) }
                Button("Test Codex Helper") { runSelfTest(.codex) }
                Button("Test Claude Helper") { runSelfTest(.claudeCode) }
                if testing { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
            Text("Reads the installed config, helper, bridge state and observed traffic. It never installs, starts or injects a synthetic session.")
                .font(.caption2).foregroundStyle(.tertiary)

            if let result = selfTest {
                ForEach(result.stages) { stage in
                    HStack(spacing: 6) {
                        Image(systemName: icon(stage.ok))
                            .foregroundStyle(color(stage.ok)).font(.system(size: 10))
                        Text("\(stage.index). \(stage.name)").font(.caption)
                            .frame(width: 190, alignment: .leading)
                        Text(stage.detail).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(result.summary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func icon(_ ok: Bool?) -> String {
        switch ok { case .some(true): return "checkmark.circle.fill"
                    case .some(false): return "xmark.octagon.fill"
                    case .none: return "circle" }
    }
    private func color(_ ok: Bool?) -> Color {
        switch ok { case .some(true): return .green; case .some(false): return .red; case .none: return .secondary }
    }

    private func runSelfTest(_ provider: TerminalAgentProvider) {
        testing = true; selfTest = nil
        Task {
            let result = await TerminalSelfTest.run(provider: provider, env: env)
            selfTest = result
            testing = false
        }
    }

    // MARK: Runtime counters

    private var countersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Runtime counters")
            counter("Bridge started", stats.startedAt.map { "\($0)" } ?? "not started")
            counter("Socket path", stats.socketPath)
            counter("Socket owner/perms", stats.socketOwnerPermissions)
            counter("Raw connections", "\(stats.rawConnections)")
            counter("Decoded events", "\(stats.decodedEvents)")
            counter("Rejected events", "\(stats.rejectedEvents)")
            counter("Last decode error", stats.lastDecodeError)
            counter("Store sessions", "\(stats.storeCount)")
            counter("Connected", "\(stats.connectedCount)")
            counter("External", "\(stats.externalCount)")
            counter("Agents UI observed", "\(env.agentStore.sessions.count)")
            counter("Last UI refresh", stats.lastUIRefreshAt.map { "\($0)" } ?? "—")
        }
    }

    private func counter(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.caption2).foregroundStyle(.tertiary).frame(width: 140, alignment: .leading)
            Text(v).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    // MARK: Helper log

    private var logSection: some View {
        HStack(spacing: 8) {
            SectionLabel(text: "Helper log")
            Spacer()
            Button("Reveal Hook Log") {
                if !FileManager.default.fileExists(atPath: hookLogURL.path) {
                    try? "".write(to: hookLogURL, atomically: true, encoding: .utf8)
                }
                NSWorkspace.shared.activateFileViewerSelecting([hookLogURL])
            }
            Button("Clear Hook Log") {
                try? FileManager.default.removeItem(at: hookLogURL)
                message = "Hook log cleared."
            }
        }
        .controlSize(.small)
    }
}

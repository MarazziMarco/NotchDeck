import SwiftUI

/// The Agents face: a monitor, approval surface and fast terminal switcher for
/// sessions already running in real terminals. No New-session composer here —
/// NotchDeck observes hook-connected and external sessions, not a launcher.
struct AgentsFaceView: View {
    @EnvironmentObject private var store: AgentSessionStore
    @EnvironmentObject private var coordinator: AgentCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var env: AppEnvironment

    enum Tab: String { case active, recent }
    @State private var tab: Tab = .active

    private var active: [AgentSession] { store.activeSessions }
    private var recent: [AgentSession] { store.recentSessions }

    var body: some View {
        VStack(spacing: 8) {
            header
            tabBar
            if let msg = coordinator.lastFocusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(msg).lineLimit(2)
                    Spacer(minLength: 0)
                    Button { coordinator.lastFocusMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.statusAttention)
                .padding(.horizontal, 12)
            }
            content
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await coordinator.refreshAvailability()
            coordinator.refreshExternalSessions()
        }
        .onAppear { env.terminalStats.noteUIRefresh(count: store.sessions.count) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Agents").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.primaryText)
            if coordinator.externalControlEnabled && !coordinator.accessibilityTrusted {
                Label("Grant Accessibility", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 9.5)).foregroundStyle(DesignTokens.Palette.statusAttention)
            }
            Spacer()
            if !active.isEmpty {
                miniStat("\(active.count)", "bolt.fill", DesignTokens.Palette.statusRunning)
            }
            let approvals = active.filter { $0.hasLiveApproval }.count
            if approvals > 0 {
                miniStat("\(approvals)", "exclamationmark", DesignTokens.Palette.statusApproval)
            }
        }
        .padding(.horizontal, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.active, "Active", active.count)
            tabButton(.recent, "Recent", recent.count)
            Spacer()
            if tab == .recent && !recent.isEmpty {
                Button("Clear Recent") { store.clearRecent() }
                    .buttonStyle(.plain).font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, 12)
    }

    private func tabButton(_ t: Tab, _ label: String, _ count: Int) -> some View {
        let selected = tab == t
        return Button { tab = t } label: {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 11.5, weight: .semibold))
                if count > 0 {
                    Text("\(count)").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(DesignTokens.Palette.cardFill, in: Capsule())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(selected ? DesignTokens.Palette.cardFillHover : .clear, in: Capsule())
            .foregroundStyle(selected ? DesignTokens.Palette.primaryText : DesignTokens.Palette.tertiaryText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        let list = tab == .active ? active : recent
        if list.isEmpty {
            tab == .active ? AnyView(activeEmptyState) : AnyView(recentEmptyState)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(list) { session in
                        AgentSessionCard(
                            session: session,
                            maxPreviewLines: settings.settings.agentMaxPreviewLines,
                            showPreview: settings.settings.latestMessagePreviewEnabled,
                            approvalSending: coordinator.approvalInFlight.contains(session.id),
                            actions: actions(for: session))
                        .opacity(tab == .recent ? 0.82 : 1)   // Recent is visually secondary
                        .contentShape(Rectangle())
                        .onTapGesture { appState.focusAgent(session.id) }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
    }

    private func actions(for session: AgentSession) -> AgentCardActions {
        // Allow/Deny ONLY for a live approval whose mode shows a functional
        // decision (never terminalOnly, never after fallback).
        let canDecide = session.hasLiveApproval
            && session.approval?.state == .pending
            && (session.approval?.handlingMode.showsFunctionalDecision ?? false)
            && (session.isBridgeConnected || session.isManaged)
        return AgentCardActions(
            focusTerminal: { coordinator.focusTerminal(session) },
            openProject: { coordinator.openProject(session) },
            approve: canDecide ? { Task { await coordinator.decide(session: session, allow: true) } } : nil,
            deny: canDecide ? { Task { await coordinator.decide(session: session, allow: false) } } : nil,
            resume: session.isManaged ? { Task { await coordinator.resume(sessionID: session.id) } } : nil,
            interrupt: session.isManaged ? { Task { await coordinator.interrupt(sessionID: session.id) } } : nil,
            followUp: nil)
    }

    private func miniStat(_ n: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(n).font(.system(size: 10, weight: .semibold))
        }.foregroundStyle(color)
    }

    private var activeEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal").font(.system(size: 30))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            Text("No active agent sessions").font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Text("Start Claude Code, Codex or another agent in your terminal. Sessions started after installing the NotchDeck hook appear here automatically.")
                .font(.system(size: 10.5)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private var recentEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 24))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            Text("No recent sessions").font(.system(size: 12))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

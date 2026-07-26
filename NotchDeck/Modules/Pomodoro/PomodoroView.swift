import SwiftUI

/// Shared progress ring used by both the compact and expanded Pomodoro views.
struct ProgressRing: View {
    var progress: Double            // 0…1
    var lineWidth: CGFloat = 6
    var tint: Color
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
    }
}

extension PomodoroPhase {
    var tint: Color {
        switch self {
        case .work: return DesignTokens.Palette.statusRunning
        case .shortBreak: return DesignTokens.Palette.statusSuccess
        case .longBreak: return DesignTokens.Palette.statusApproval
        case .idle: return DesignTokens.Palette.statusIdle
        }
    }
}

@MainActor
struct PomodoroModel {
    let service: PomodoroService
    var phase: PomodoroPhase { service.engine.phase }
    var isRunning: Bool { service.engine.isRunning }
    var sessions: Int { service.engine.completedWorkSessions }
    var time: String { service.formattedRemaining }
    var progress: Double {
        let duration = service.engine.config.duration(for: phase)
        guard duration > 0 else { return 0 }
        let remaining = service.remaining
        return (duration - remaining) / duration
    }
}

/// Tiny live-activity shown in the compact notch while the timer runs — a small
/// progress ring + focus icon and the remaining time in MM:SS. Driven entirely
/// by the app-scoped service (timestamp source of truth); it never creates a
/// second timer, survives collapse/face-switch, and clicking the notch expands
/// (handled by the interaction layer) without pinning.
struct PomodoroLiveActivity: View {
    @EnvironmentObject private var service: PomodoroService
    private var m: PomodoroModel { PomodoroModel(service: service) }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                ProgressRing(progress: m.progress, lineWidth: 2, tint: m.phase.tint)
                    .frame(width: 14, height: 14)
                Image(systemName: "timer").font(.system(size: 7))
                    .foregroundStyle(m.phase.tint)
            }
            Text(m.time)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .transition(.opacity)
    }
}

/// Premium compact Pomodoro card for the Utilities side column.
struct PomodoroCompactCard: View {
    @EnvironmentObject private var service: PomodoroService
    private var m: PomodoroModel { PomodoroModel(service: service) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ProgressRing(progress: m.progress, lineWidth: 4, tint: m.phase.tint)
                    .frame(width: 40, height: 40)
                Image(systemName: "timer").font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(m.phase.label.uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(m.phase.tint)
                Text(m.time)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.primaryText)
            }
            Spacer(minLength: 0)
            Button(action: primaryAction) {
                Image(systemName: m.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(DesignTokens.Palette.cardFillHover, in: Circle())
                    .foregroundStyle(DesignTokens.Palette.primaryText)
            }
            .buttonStyle(.plain)
        }
        .dashboardCard()
    }

    private func primaryAction() {
        if m.isRunning { service.pause() }
        else if m.phase == .idle { service.start() }
        else { service.resume() }
    }
}

/// Expanded Pomodoro — large ring, session label, refined controls.
struct PomodoroExpandedView: View {
    @EnvironmentObject private var service: PomodoroService
    private var m: PomodoroModel { PomodoroModel(service: service) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: m.progress, lineWidth: 8, tint: m.phase.tint)
                    .frame(width: 132, height: 132)
                VStack(spacing: 2) {
                    Text(m.time)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    Text(m.phase.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(m.phase.tint)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<max(1, service.engine.config.sessionsBeforeLongBreak), id: \.self) { i in
                    Circle()
                        .fill(i < (m.sessions % service.engine.config.sessionsBeforeLongBreak)
                              ? m.phase.tint : Color.white.opacity(0.12))
                        .frame(width: 6, height: 6)
                }
            }
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Metrics.contentPadding)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if m.isRunning {
                pillButton("Pause", "pause.fill", filled: true) { service.pause() }
            } else if m.phase == .idle {
                pillButton("Start", "play.fill", filled: true) { service.start() }
            } else {
                pillButton("Resume", "play.fill", filled: true) { service.resume() }
            }
            pillButton("Skip", "forward.fill", filled: false) { service.skip() }
            pillButton("Reset", "arrow.counterclockwise", filled: false) { service.reset() }
        }
    }

    private func pillButton(_ title: String, _ icon: String, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(filled ? m.phase.tint.opacity(0.22) : DesignTokens.Palette.cardFill,
                            in: Capsule())
                .foregroundStyle(filled ? m.phase.tint : DesignTokens.Palette.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

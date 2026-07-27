import SwiftUI

/// Pure representation of where the user is in the work→break cycle. The cycle
/// is four focus blocks (work · short break) ×3 then a long break.
struct PomodoroCycle: Equatable {
    var filledSlices: Int      // completed focus blocks in the current cycle (0…total)
    var totalSlices: Int       // == sessionsBeforeLongBreak
    var isLongBreak: Bool
    var isBreak: Bool

    static func compute(completedWorkSessions: Int, sessionsBeforeLongBreak: Int,
                        phase: PomodoroPhase) -> PomodoroCycle {
        let total = max(1, sessionsBeforeLongBreak)
        let inCycle = completedWorkSessions % total
        let filled = (phase == .longBreak) ? total : inCycle
        return PomodoroCycle(filledSlices: filled, totalSlices: total,
                             isLongBreak: phase == .longBreak,
                             isBreak: phase == .shortBreak || phase == .longBreak)
    }
}

/// The Focus tab — a dedicated, colourful Pomodoro page.
struct PomodoroFocusPage: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var settings: SettingsStore

    private var m: PomodoroModel { PomodoroModel(service: service) }
    private var cycle: PomodoroCycle {
        PomodoroCycle.compute(completedWorkSessions: service.engine.completedWorkSessions,
                              sessionsBeforeLongBreak: service.engine.config.sessionsBeforeLongBreak,
                              phase: m.phase)
    }

    var body: some View {
        GeometryReader { geo in
            // Above the breakpoint use a horizontal dashboard (timer left, session
            // info + grouped controls right) filling ~75–80% of the width; below
            // it, the vertical stack. Same information and controls in both.
            if FocusLayout.isHorizontal(availableWidth: geo.size.width) {
                horizontal(width: geo.size.width)
            } else {
                vertical
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Metrics.contentPadding)
        // No redundant "Focus" title is drawn (the tab bar identifies the page and
        // the timer's phase label is meaningful state, not a heading). The semantic
        // page title is preserved for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(UtilitiesTab.focus.title))
    }

    private var vertical: some View {
        VStack(spacing: 12) {
            timer
            slices
            controls
            completedLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func horizontal(width: CGFloat) -> some View {
        HStack(spacing: 28) {
            timer.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.phase.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                    Text("\(cycle.filledSlices) of \(cycle.totalSlices) completed")
                        .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.secondaryText)
                    slices.padding(.top, 2)
                }
                controls
                completedLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: min(width * 0.8, width - 48))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completedLabel: some View {
        Text("\(service.engine.completedWorkSessions) focus sessions completed")
            .font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
    }

    private var timer: some View {
        ZStack {
            switch settings.settings.pomodoroWidgetStyle {
            case .tomato: TomatoShape(progress: m.progress, accent: accent).frame(width: 120, height: 120)
            default: ProgressRing(progress: m.progress, lineWidth: 8, tint: accent).frame(width: 120, height: 120)
            }
            VStack(spacing: 2) {
                Text(m.time).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                Text(m.phase.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            }
        }
    }

    private var accent: Color {
        if settings.settings.pomodoroWidgetStyle == .monochrome { return .white.opacity(0.85) }
        return m.phase.tint
    }

    /// Four cycle slices — filled = completed focus blocks; the current one pulses.
    private var slices: some View {
        HStack(spacing: 6) {
            ForEach(0..<cycle.totalSlices, id: \.self) { i in
                Capsule()
                    .fill(i < cycle.filledSlices ? accent : Color.white.opacity(0.12))
                    .frame(width: 30, height: 6)
                    .overlay(
                        Capsule().stroke(i == cycle.filledSlices && !cycle.isBreak ? accent : .clear, lineWidth: 1)
                    )
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if m.isRunning {
                pill("Pause", "pause.fill", filled: true) { service.pause() }
            } else if m.phase == .idle {
                pill("Start", "play.fill", filled: true) { service.start() }
            } else {
                pill("Resume", "play.fill", filled: true) { service.resume() }
            }
            pill("Skip", "forward.fill", filled: false) { service.skip() }
            pill("Reset", "arrow.counterclockwise", filled: false) { service.reset() }
        }
    }

    private func pill(_ title: String, _ icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(filled ? accent.opacity(0.22) : DesignTokens.Palette.cardFill, in: Capsule())
                .foregroundStyle(filled ? accent : DesignTokens.Palette.secondaryText)
        }.buttonStyle(.plain)
    }
}

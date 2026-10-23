import SwiftUI
import SharedWidgets

/// A native summary for the shallow More rows. Full editors open in Focus.
struct NotchSharedWidgetSummary: View {
    let moduleID: String
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var countdown = SharedWidgetLibrary.shared.countdown
    @ObservedObject private var habits = SharedWidgetLibrary.shared.habits

    private var isHabits: Bool { moduleID == "sharedHabits" }
    private var isRoutine: Bool { moduleID == "sharedRoutine" }
    private var title: String { isRoutine ? "Routine · Palestra" : (isHabits ? "Abitudini" : "Conto alla rovescia") }
    private var symbol: String { isRoutine ? "dumbbell" : (isHabits ? "checkmark.circle" : "flag.checkered") }
    private var accent: Color { isRoutine ? .orange : (isHabits ? .mint : .purple) }

    var body: some View {
        Button { appState.focusModule(moduleID) } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: symbol).foregroundStyle(accent)
                        Text(title).foregroundStyle(DesignTokens.Palette.secondaryText)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    }.font(.system(size: 11, weight: .semibold))
                    if isRoutine {
                        Text("Scheda e planning").font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.Palette.primaryText)
                        Text("Apri gli esercizi e le registrazioni di Routine")
                            .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.tertiaryText).lineLimit(1)
                    } else if isHabits {
                        let scheduled = habits.value.habits.filter { $0.isScheduled(on: context.date) }
                        let completed = scheduled.filter { $0.count(on: context.date) >= max(1, $0.definition.target) }.count
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(completed)/\(scheduled.count)").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                            Text("oggi").font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                        }
                        Text(habits.value.habits.isEmpty ? "Aggiungi le tue abitudini" : (scheduled.isEmpty ? "Nessuna abitudine prevista oggi" : scheduled.prefix(3).map { $0.definition.title }.joined(separator: " · ")))
                            .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.secondaryText).lineLimit(1)
                    } else {
                        let parts = countdown.value.remaining(at: context.date)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(countdown.value.target <= context.date ? "Ci siamo!" : (parts.days > 0 ? "\(parts.days) giorni" : String(format: "%02d:%02d", parts.hours, parts.minutes)))
                                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(accent).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        Text(countdown.value.title + " · " + countdown.value.target.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.secondaryText).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help("Apri \(title)")
        .accessibilityLabel("Apri \(title)")
    }
}

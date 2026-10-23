import SwiftUI

struct SharedFocusCard: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedFocus>
    private let controller: SharedFocusController
    let isEditing: Bool
    @State private var flipped = false
    @State private var config = FocusConfig()
    @State private var preferences = FocusPreferences()
    @State private var actionError: String?
    init(library: SharedWidgetLibrary, isEditing: Bool, initiallyFlipped: Bool = false) {
        channel = library.focus; controller = library.focusController; self.isEditing = isEditing
        _flipped = State(initialValue: initiallyFlipped); _config = State(initialValue: library.focus.value.engine.config); _preferences = State(initialValue: library.focus.value.preferences)
    }
    var body: some View {
        ReversibleWidgetCard(kind: .focus, accent: TimetableColors.color(channel.value.preferences.color), flipped: $flipped,
                             isEditing: isEditing, onEdit: edit, onSave: save) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let engine = channel.value.engine
                let remaining = engine.phase == .idle ? engine.config.duration(for: .work) : engine.remaining(at: context.date)
                let duration = engine.config.duration(for: engine.phase == .idle ? .work : engine.phase)
                VStack(spacing: 7) {
                    Text(channel.value.preferences.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    GeometryReader { geometry in
                        let size = max(1, min(geometry.size.width, geometry.size.height, 180))
                        ZStack {
                            Circle().stroke(.white.opacity(0.07), lineWidth: 6)
                            Circle().trim(from: 0, to: min(1, max(0, 1 - remaining / max(1, duration))))
                                .stroke(TimetableColors.color(channel.value.preferences.color), style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 3) {
                                Text(engine.phase.label.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.6))
                                Text(String(format: "%02d:%02d", Int(ceil(remaining)) / 60, Int(ceil(remaining)) % 60))
                                    .font(.system(size: min(48, size * 0.27), weight: .light, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
                            }
                        }
                        .frame(width: max(1, size - 8), height: max(1, size - 8)).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    HStack(spacing: 15) {
                        Button { perform { try controller.reset() } } label: { Image(systemName: "arrow.counterclockwise") }.help("Ricomincia il ciclo")
                        Button { perform { try controller.toggle() } } label: {
                            Label(engine.isRunning ? "Pausa" : (engine.phase == .idle ? "Avvia" : "Riprendi"), systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                        }.buttonStyle(.borderedProminent).tint(TimetableColors.color(channel.value.preferences.color).opacity(0.75))
                        Button { perform { try controller.skip() } } label: { Image(systemName: "forward.end.fill") }.help("Passa alla fase successiva")
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    Text("\(engine.completedWorkSessions) sessioni completate").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    WidgetActionError(message: actionError ?? channel.errorMessage)
                }
            }
        } settings: {
            TextField("Obiettivo della sessione", text: $preferences.title).textFieldStyle(.roundedBorder)
            Stepper("Focus: \(config.workMinutes) min", value: $config.workMinutes, in: 1...120)
            Stepper("Pausa breve: \(config.shortBreakMinutes) min", value: $config.shortBreakMinutes, in: 1...30)
            Stepper("Pausa lunga: \(config.longBreakMinutes) min", value: $config.longBreakMinutes, in: 1...60)
            Stepper("Pausa lunga ogni \(config.sessionsBeforeLongBreak) sessioni", value: $config.sessionsBeforeLongBreak, in: 2...8)
            Toggle("Avvia la fase successiva", isOn: $preferences.autoAdvance)
            Toggle("Suono a fine fase", isOn: $preferences.completionSound)
            WidgetColorPicker(title: "Colore", hex: $preferences.color)
        }
        .font(.system(size: 12))
    }
    private func edit() { config = channel.value.engine.config; preferences = channel.value.preferences; flipped = true }
    private func save() throws {
        guard !preferences.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TimetableImportError("Inserisci un obiettivo o un titolo.") }
        try channel.update { $0.engine.config = config; $0.preferences = preferences }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); actionError = nil } catch { actionError = error.localizedDescription } }
}

struct SharedCountdownCard: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedCountdown>
    let isEditing: Bool
    @State private var flipped = false
    @State private var draft = SharedCountdown()
    init(library: SharedWidgetLibrary, isEditing: Bool, initiallyFlipped: Bool = false) { channel = library.countdown; self.isEditing = isEditing; _flipped = State(initialValue: initiallyFlipped); _draft = State(initialValue: library.countdown.value) }
    var body: some View {
        ReversibleWidgetCard(kind: .countdown, accent: TimetableColors.color(channel.value.color), flipped: $flipped, isEditing: isEditing,
                             onEdit: { draft = channel.value; flipped = true }, onSave: save) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let value = channel.value
                let remaining = value.remaining(at: context.date)
                VStack(spacing: 8) {
                    Image(systemName: value.symbol).font(.system(size: 22, weight: .light)).foregroundStyle(TimetableColors.color(value.color))
                    Text(value.title).font(.system(size: 17, weight: .semibold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2)
                    Spacer(minLength: 0)
                    if value.target <= context.date {
                        Text("Ci siamo!").font(.system(size: 34, weight: .light, design: .rounded))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(remaining.days)").font(.system(size: 58, weight: .light, design: .rounded).monospacedDigit())
                            Text(remaining.days == 1 ? "giorno" : "giorni").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                        Text(value.showSeconds ? String(format: "%02dh  %02dm  %02ds", remaining.hours, remaining.minutes, remaining.seconds)
                                              : String(format: "%02dh  %02dm", remaining.hours, remaining.minutes))
                            .font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(TimetableColors.color(value.color))
                    }
                    Spacer(minLength: 0)
                    Text(value.target.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    WidgetActionError(message: channel.errorMessage)
                }.frame(maxWidth: .infinity)
            }
        } settings: {
            TextField("Nome dell’evento", text: $draft.title).textFieldStyle(.roundedBorder)
            DatePicker("Scadenza", selection: $draft.target, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.compact)
            Picker("Simbolo", selection: $draft.symbol) {
                Label("Traguardo", systemImage: "flag.checkered").tag("flag.checkered")
                Label("Esame", systemImage: "graduationcap").tag("graduationcap")
                Label("Viaggio", systemImage: "airplane").tag("airplane")
                Label("Evento", systemImage: "calendar").tag("calendar")
                Label("Compleanno", systemImage: "gift").tag("gift")
            }
            Toggle("Mostra secondi", isOn: $draft.showSeconds)
            WidgetColorPicker(title: "Colore", hex: $draft.color)
        }
        .font(.system(size: 12))
    }
    private func save() throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TimetableImportError("Inserisci il nome dell’evento.") }
        try channel.update { $0 = draft }
    }
}

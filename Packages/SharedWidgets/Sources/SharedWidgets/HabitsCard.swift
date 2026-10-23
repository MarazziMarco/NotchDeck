import SwiftUI

struct SharedHabitsCard: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedHabits>
    let isEditing: Bool
    @State private var flipped = false
    @State private var definitions: [HabitDefinition] = []
    @State private var title = ""
    @State private var showCompleted = true
    @State private var actionError: String?
    init(library: SharedWidgetLibrary, isEditing: Bool, initiallyFlipped: Bool = false) {
        channel = library.habits; self.isEditing = isEditing
        _flipped = State(initialValue: initiallyFlipped); _definitions = State(initialValue: library.habits.value.habits.map(\.definition))
        _title = State(initialValue: library.habits.value.title); _showCompleted = State(initialValue: library.habits.value.showCompleted)
    }
    var body: some View {
        ReversibleWidgetCard(kind: .habits, accent: Color(red: 0.44, green: 0.83, blue: 0.68), flipped: $flipped, isEditing: isEditing,
                             onEdit: edit, onSave: save) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let scheduled = channel.value.habits.filter { $0.isScheduled(on: context.date) }
                let complete = scheduled.filter { $0.count(on: context.date) >= max(1, $0.definition.target) }.count
                let visible = scheduled.filter { channel.value.showCompleted || $0.count(on: context.date) < max(1, $0.definition.target) }
                VStack(alignment: .leading, spacing: 10) {
                    Text(channel.value.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    if channel.value.habits.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "leaf").font(.system(size: 32, weight: .light)).foregroundStyle(.mint)
                            Text("Costruisci la tua routine").font(.system(size: 15, weight: .semibold, design: .rounded))
                            Button("Aggiungi abitudine") { edit() }.buttonStyle(.borderedProminent).tint(.mint.opacity(0.6))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical) {
                            VStack(spacing: 7) {
                                ForEach(visible) { habit in habitRow(habit, now: context.date) }
                                if visible.isEmpty {
                                    Label(scheduled.isEmpty ? "Oggi non hai abitudini in programma" : "Tutte fatte per oggi!", systemImage: scheduled.isEmpty ? "sun.max" : "checkmark.seal.fill")
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.mint).padding(.vertical, 20)
                                }
                            }
                        }.scrollIndicators(.hidden)
                        HStack {
                            Text("\(complete)/\(scheduled.count) oggi").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                            ProgressView(value: Double(complete), total: Double(max(1, scheduled.count))).tint(.mint)
                        }
                    }
                    WidgetActionError(message: actionError ?? channel.errorMessage)
                }
            }
        } settings: {
            TextField("Titolo del widget", text: $title).textFieldStyle(.roundedBorder)
            Toggle("Mostra anche le completate", isOn: $showCompleted)
            ForEach($definitions) { $definition in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField("Nome abitudine", text: $definition.title).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { definitions.removeAll { $0.id == definition.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).help("Rimuovi abitudine quando salvi")
                    }
                    Picker("Simbolo", selection: $definition.symbol) {
                        Label("Spunta", systemImage: "checkmark").tag("checkmark")
                        Label("Acqua", systemImage: "drop.fill").tag("drop.fill")
                        Label("Lettura", systemImage: "book").tag("book")
                        Label("Movimento", systemImage: "figure.walk").tag("figure.walk")
                        Label("Focus", systemImage: "brain.head.profile").tag("brain.head.profile")
                    }
                    Stepper("Obiettivo: \(definition.target) al giorno", value: $definition.target, in: 1...20)
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if definition.weekdays.contains(day) { definition.weekdays.removeAll { $0 == day } }
                                else { definition.weekdays.append(day) }
                            } label: {
                                Text(["L", "M", "M", "G", "V", "S", "D"][day - 1])
                                    .font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 24)
                                    .background(definition.weekdays.contains(day) ? .mint.opacity(0.35) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain).accessibilityLabel(["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"][day - 1])
                        }
                    }
                    WidgetColorPicker(title: "Colore", hex: $definition.color)
                }
                .padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            Button { definitions.append(HabitDefinition()) } label: { Label("Aggiungi abitudine", systemImage: "plus") }
                .disabled(definitions.count >= 12)
            Text("Le spunte e le serie rimangono salvate. Per eliminare un’abitudine e la sua cronologia, rimuovila e premi Save.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 12))
    }
    private func habitRow(_ habit: HabitRecord, now: Date) -> some View {
        let count = habit.count(on: now)
        let done = count >= max(1, habit.definition.target)
        let color = TimetableColors.color(habit.definition.color)
        return Button {
            do { try channel.update { $0.toggle(habit.id, on: now) }; actionError = nil }
            catch { actionError = error.localizedDescription }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(done ? 0.24 : 0.08)).frame(width: 32, height: 32)
                    Image(systemName: done ? "checkmark" : habit.definition.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.definition.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    let streak = habit.streak(at: now)
                    if streak > 0 { Text("\(streak) giorni di fila").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)) }
                }
                Spacer(minLength: 0)
                Text("\(count)/\(max(1, habit.definition.target))").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(color)
            }
            .padding(8).background(.white.opacity(done ? 0.025 : 0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(habit.definition.title), \(count) di \(habit.definition.target)")
        .contextMenu {
            Button("Annulla un segno") {
                do {
                    try channel.update { state in
                        guard let index = state.habits.firstIndex(where: { $0.id == habit.id }) else { return }
                        let key = SharedHabits.dayKey(now)
                        state.habits[index].days[key] = max(0, (state.habits[index].days[key] ?? 0) - 1)
                    }
                } catch { actionError = error.localizedDescription }
            }.disabled(count == 0)
        }
    }
    private func edit() {
        title = channel.value.title; showCompleted = channel.value.showCompleted; definitions = channel.value.habits.map(\.definition)
        flipped = true
    }
    private func save() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TimetableImportError("Inserisci un titolo.") }
        guard definitions.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.weekdays.isEmpty }) else {
            throw TimetableImportError("Ogni abitudine richiede un nome e almeno un giorno della settimana.")
        }
        try channel.update { $0.configure(definitions, title: title, showCompleted: showCompleted) }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Timetable: import a `notchdeck-timetable` file, choose the courses
/// you follow, and add / edit / delete single lessons.
struct TimetableSettingsView: View {
    @EnvironmentObject private var store: TimetableStore

    @State private var importErrors: [String] = []
    @State private var importMessage: String?
    @State private var editing: TimetableLesson?
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "Timetable file") { fileSection }
            if let timetable = store.timetable {
                SettingsGroup(title: "Courses you follow") { coursesSection(timetable) }
                SettingsGroup(title: "Lessons") { lessonsSection(timetable) }
            }
        }
    }

    // MARK: File

    @ViewBuilder private var fileSection: some View {
        if let timetable = store.timetable {
            VStack(alignment: .leading, spacing: 2) {
                Text(timetable.title ?? "Imported timetable").fontWeight(.medium)
                Text(summary(timetable)).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("No timetable imported. Import a JSON file in the notchdeck-timetable format.")
                .font(.callout).foregroundStyle(.secondary)
        }
        HStack {
            Button(store.timetable == nil ? "Import Timetable…" : "Replace Timetable…", action: chooseFile)
            if store.timetable != nil {
                Button("Remove", role: .destructive) { confirmRemove = true }
            }
        }
        .confirmationDialog("Remove the timetable?", isPresented: $confirmRemove) {
            Button("Remove Timetable", role: .destructive) { store.removeTimetable() }
        } message: {
            Text("Course notes and exams are kept and come back if you import the same courses again.")
        }
        if let importMessage {
            Text(importMessage).font(.caption).foregroundStyle(.green)
        }
        if !importErrors.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("The file was not imported:").font(.caption.weight(.semibold))
                ForEach(importErrors, id: \.self) { Text("• \($0)").font(.caption.monospaced()) }
            }
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
        Text("Re-importing replaces courses and lessons; notes, exams and followed courses are kept per course id. Everything stays on this Mac.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(_ t: Timetable) -> String {
        var parts = ["\(t.courses.count) courses", "\(t.lessons.count) lessons"]
        if let term = t.term { parts.append("\(term.start) → \(term.end)") }
        return parts.joined(separator: " · ")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importErrors = []
        importMessage = nil
        guard let data = try? Data(contentsOf: url) else {
            importErrors = ["The file could not be read."]
            return
        }
        switch store.importFile(data) {
        case .success(let timetable):
            importMessage = "Imported \(timetable.courses.count) courses and \(timetable.lessons.count) lessons."
        case .failure(let error):
            importErrors = error.messages
        }
    }

    // MARK: Courses

    private func coursesSection(_ timetable: Timetable) -> some View {
        let groups = Dictionary(grouping: timetable.courses) { $0.group ?? "Courses" }
        let order = timetable.courses.map { $0.group ?? "Courses" }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(order, id: \.self) { group in
                VStack(alignment: .leading, spacing: 4) {
                    if order.count > 1 {
                        Text(group).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(groups[group] ?? []) { course in
                        Toggle(isOn: Binding(get: { store.isFollowed(course.id) },
                                             set: { store.setFollowed(course.id, $0) })) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(timetableHex: TimetableSchedule.colorHex(
                                        for: course, among: timetable.courses.map(\.id))))
                                    .frame(width: 8, height: 8)
                                Text(course.short).font(.callout.weight(.semibold)).frame(minWidth: 44, alignment: .leading)
                                Text(course.name).font(.callout)
                                if let professor = course.professor {
                                    Text(professor).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Lessons

    private func lessonsSection(_ timetable: Timetable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(timetable.lessons) { lesson in
                if editing?.id == lesson.id, let draft = editing {
                    TimetableLessonEditor(lesson: draft, timetable: timetable,
                                          onSave: { store.updateLesson($0); editing = nil },
                                          onCancel: { editing = nil })
                } else {
                    lessonRow(lesson, timetable: timetable)
                }
            }
            if let draft = editing, !timetable.lessons.contains(where: { $0.id == draft.id }) {
                TimetableLessonEditor(lesson: draft, timetable: timetable,
                                      onSave: { store.addLesson($0); editing = nil },
                                      onCancel: { editing = nil })
            }
            Button("Add Lesson") {
                editing = TimetableLesson(courseID: timetable.courses.first?.id ?? "", day: .mon,
                                          start: ClockTime(minutes: 9 * 60), end: ClockTime(minutes: 11 * 60))
            }
            .disabled(editing != nil || timetable.courses.isEmpty)
        }
    }

    private func lessonRow(_ lesson: TimetableLesson, timetable: Timetable) -> some View {
        let course = timetable.course(id: lesson.courseID)
        return HStack(spacing: 8) {
            Text(lesson.day.shortLabel).frame(width: 32, alignment: .leading)
            Text(course?.short ?? lesson.courseID).fontWeight(.semibold).frame(width: 52, alignment: .leading)
            Text(TimetableText.timeAndPlace(lesson, timetable: timetable)).monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button { editing = lesson } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .disabled(editing != nil)
                .accessibilityLabel(Text("Edit lesson"))
            Button(role: .destructive) { store.deleteLesson(lesson.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(editing != nil)
                .accessibilityLabel(Text("Delete lesson"))
        }
        .font(.callout)
    }
}

/// Inline add/edit form for one lesson. Times are typed as HH:mm and must form
/// a valid range before Save is enabled.
private struct TimetableLessonEditor: View {
    let timetable: Timetable
    let onSave: (TimetableLesson) -> Void
    let onCancel: () -> Void

    @State private var draft: TimetableLesson
    @State private var startText: String
    @State private var endText: String
    @State private var roomText: String

    init(lesson: TimetableLesson, timetable: Timetable,
         onSave: @escaping (TimetableLesson) -> Void, onCancel: @escaping () -> Void) {
        self.timetable = timetable
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: lesson)
        _startText = State(initialValue: lesson.start.text)
        _endText = State(initialValue: lesson.end.text)
        _roomText = State(initialValue: lesson.room ?? "")
    }

    private var start: ClockTime? { ClockTime(startText) }
    private var end: ClockTime? { ClockTime(endText) }
    private var isValid: Bool {
        guard let start, let end else { return false }
        return start < end && timetable.course(id: draft.courseID) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Course", selection: $draft.courseID) {
                    ForEach(timetable.courses) { Text($0.name).tag($0.id) }
                }
                Picker("Day", selection: $draft.day) {
                    ForEach(Weekday.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                }
                .frame(width: 120)
            }
            HStack {
                TextField("Start", text: $startText).frame(width: 64)
                Text("–")
                TextField("End", text: $endText).frame(width: 64)
                TextField("Room", text: $roomText)
                Picker("Location", selection: $draft.locationID) {
                    Text("None").tag(String?.none)
                    ForEach(timetable.locations) { Text($0.name).tag(String?.some($0.id)) }
                }
                .frame(width: 180)
            }
            if !isValid {
                Text("Times are HH:mm and the start must be before the end.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel", action: onCancel)
                Button("Save") {
                    guard let start, let end else { return }
                    var lesson = draft
                    lesson.start = start
                    lesson.end = end
                    let room = roomText.trimmingCharacters(in: .whitespaces)
                    lesson.room = room.isEmpty ? nil : room
                    onSave(lesson)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

import AppKit
import SwiftUI

/// One course, in place of the Timetable overview: weekly lessons with a Maps
/// shortcut, the fixed course note, notes for the next lessons, and exams.
struct TimetableCourseSheet: View {
    @EnvironmentObject private var store: TimetableStore
    let course: TimetableCourse
    let timetable: Timetable
    let onBack: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                lessonsAndNote.frame(maxWidth: .infinity, alignment: .topLeading)
                nextLessons.frame(maxWidth: .infinity, alignment: .topLeading)
                TimetableExamsColumn(courseID: course.id).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var color: Color {
        Color(timetableHex: TimetableSchedule.colorHex(for: course, among: timetable.courses.map(\.id)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("Timetable", systemImage: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            .buttonStyle(.plain)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(course.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let professor = course.professor {
                Text(professor)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Weekly lessons + fixed note

    private var lessonsAndNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnTitle("Every week")
            ForEach(timetable.lessons.filter { $0.courseID == course.id }) { lesson in
                HStack(spacing: 6) {
                    Text(lesson.day.shortLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, alignment: .leading)
                    Text(TimetableText.timeAndPlace(lesson, timetable: timetable))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let url = TimetableSchedule.mapsURL(room: lesson.room,
                                                           location: timetable.location(id: lesson.locationID)) {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Image(systemName: "map").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignTokens.Palette.statusRunning)
                        .help("Open in Maps")
                        .accessibilityLabel(Text("Open \(lesson.room ?? "room") in Maps"))
                    }
                }
            }
            columnTitle("Course note").padding(.top, 4)
            TextEditor(text: Binding(get: { store.note(course.id) },
                                     set: { store.setNote(course.id, $0) }))
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: 7))
                .frame(minHeight: 60, maxHeight: .infinity)
                .accessibilityLabel(Text("Course note"))
        }
    }

    // MARK: Next lessons with their own notes

    private var nextLessons: some View {
        let upcoming = TimetableSchedule.upcomingOccurrences(of: course.id, from: Date(), count: 4,
                                                             in: timetable, calendar: calendar)
        return VStack(alignment: .leading, spacing: 6) {
            columnTitle("Next lessons")
            if upcoming.isEmpty {
                Text("No upcoming lessons")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            ForEach(upcoming, id: \.start) { occurrence in
                let key = TimetableSchedule.dayKey(occurrence.start, calendar: calendar)
                VStack(alignment: .leading, spacing: 3) {
                    Text(occurrence.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    TextField("Note for this lesson", text: Binding(
                        get: { store.lessonNote(courseID: course.id, dayKey: key) ?? "" },
                        set: { store.setLessonNote(courseID: course.id, dayKey: key, $0) }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(DesignTokens.Palette.tertiaryText)
    }
}

// MARK: - Exams

private struct TimetableExamsColumn: View {
    @EnvironmentObject private var store: TimetableStore
    let courseID: String

    @State private var editingID: UUID?
    @State private var date = Date()
    @State private var kind: TimetableExamKind = .exam
    @State private var note = ""

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXAMS & DEADLINES")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.exams(for: courseID)) { exam in row(exam) }
                }
            }
            .frame(maxHeight: 110)
            form
        }
    }

    private func row(_ exam: TimetableExam) -> some View {
        let days = TimetableSchedule.daysUntil(exam.date, from: Date(), calendar: calendar) ?? 0
        return HStack(spacing: 6) {
            Text(TimetableText.countdown(days: days))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(days < 0 ? DesignTokens.Palette.tertiaryText
                                 : days <= 7 ? DesignTokens.Palette.statusAttention
                                 : DesignTokens.Palette.primaryText)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(exam.kind.label) · \(displayDate(exam.date))")
                    .font(.system(size: 10.5))
                if !exam.note.isEmpty {
                    Text(exam.note)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button { store.deleteExam(exam.id, courseID: courseID); if editingID == exam.id { reset() } } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Palette.tertiaryText)
            .accessibilityLabel(Text("Delete \(exam.kind.label)"))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(editingID == exam.id ? DesignTokens.Palette.cardFillHover : DesignTokens.Palette.cardFill,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { edit(exam) }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(.system(size: 11))
                Picker("", selection: $kind) {
                    ForEach(TimetableExamKind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            HStack(spacing: 4) {
                TextField("Note", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit(save)
                Button(editingID == nil ? "Add" : "Save", action: save)
                    .controlSize(.small)
                if editingID != nil {
                    Button("Cancel", action: reset).controlSize(.small)
                }
            }
        }
    }

    private func save() {
        let exam = TimetableExam(id: editingID ?? UUID(),
                                 date: TimetableSchedule.dayKey(date, calendar: calendar),
                                 kind: kind,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        store.upsertExam(exam, courseID: courseID)
        reset()
    }

    private func edit(_ exam: TimetableExam) {
        editingID = exam.id
        date = TimetableSchedule.date(fromDayKey: exam.date, calendar: calendar) ?? Date()
        kind = exam.kind
        note = exam.note
    }

    private func reset() {
        editingID = nil
        date = Date()
        kind = .exam
        note = ""
    }

    private func displayDate(_ key: String) -> String {
        guard let date = TimetableSchedule.date(fromDayKey: key, calendar: calendar) else { return key }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

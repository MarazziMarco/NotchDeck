import SwiftUI

/// The Timetable workspace (rendered by `ExpandedNotchView`): today's lessons
/// with live now/next status on the left, the week as colour blocks on the
/// right. Tapping a lesson opens its course sheet in place.
struct TimetableWorkspaceView: View {
    @EnvironmentObject private var store: TimetableStore
    @State private var openCourseID: String?

    var body: some View {
        Group {
            if let timetable = store.timetable {
                if let id = openCourseID, let course = timetable.course(id: id) {
                    TimetableCourseSheet(course: course, timetable: timetable) { openCourseID = nil }
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        overview(timetable, now: context.date)
                    }
                }
            } else {
                TimetableEmptyState(
                    symbol: "calendar.badge.plus",
                    title: "No timetable yet",
                    message: "Import a timetable file in Settings → Timetable.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func overview(_ timetable: Timetable, now: Date) -> some View {
        let followed = store.followedIDs
        if followed.isEmpty {
            TimetableEmptyState(
                symbol: "checklist",
                title: "Choose your courses",
                message: "Pick the courses you follow in Settings → Timetable.")
        } else {
            HStack(alignment: .top, spacing: 14) {
                TimetableTodayColumn(timetable: timetable, followed: followed, now: now,
                                     open: { openCourseID = $0 })
                    .frame(width: 250)
                TimetableWeekGrid(timetable: timetable, followed: followed, now: now,
                                  open: { openCourseID = $0 })
            }
        }
    }
}

// MARK: - Today

private struct TimetableTodayColumn: View {
    @EnvironmentObject private var store: TimetableStore
    let timetable: Timetable
    let followed: Set<String>
    let now: Date
    let open: (String) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let status = TimetableSchedule.status(at: now, in: timetable, followed: followed, calendar: calendar)
        let today = TimetableSchedule.lessons(on: now, in: timetable, followed: followed, calendar: calendar)
            .map { TimetableSchedule.occurrence(of: $0, on: now, calendar: calendar) }

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.system(size: 13, weight: .semibold))
                Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Spacer(minLength: 0)
            }

            if today.isEmpty {
                Text("No lessons today")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(today, id: \.lesson.id) { occurrence in
                            row(occurrence, isCurrent: occurrence == status.current)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            if let next = status.next { nextChip(next) }
        }
    }

    private func row(_ occurrence: TimetableSchedule.Occurrence, isCurrent: Bool) -> some View {
        let lesson = occurrence.lesson
        let course = timetable.course(id: lesson.courseID)
        let isPast = occurrence.end <= now
        let note = store.lessonNote(courseID: lesson.courseID,
                                    dayKey: TimetableSchedule.dayKey(now, calendar: calendar))
        return Button { open(lesson.courseID) } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(courseColor(course))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course?.name ?? lesson.courseID)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(TimetableText.timeAndPlace(lesson, timetable: timetable))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .lineLimit(1)
                    if isCurrent {
                        let left = TimetableSchedule.minutes(from: now, to: occurrence.end)
                        Text("Ends in \(TimetableText.duration(minutes: left))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(DesignTokens.Palette.statusRunning)
                        ProgressView(value: now.timeIntervalSince(occurrence.start),
                                     total: occurrence.end.timeIntervalSince(occurrence.start))
                            .progressViewStyle(.linear)
                            .tint(courseColor(course))
                    }
                    if let note {
                        Label(note, systemImage: "note.text")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignTokens.Palette.statusAttention)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(isCurrent ? DesignTokens.Palette.cardFillHover : DesignTokens.Palette.cardFill,
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(isPast ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(course?.name ?? lesson.courseID), \(TimetableText.timeAndPlace(lesson, timetable: timetable))"))
    }

    private func nextChip(_ next: TimetableSchedule.Occurrence) -> some View {
        let course = timetable.course(id: next.lesson.courseID)
        return Button { open(next.lesson.courseID) } label: {
            HStack(spacing: 6) {
                Circle().fill(courseColor(course)).frame(width: 7, height: 7)
                Text("Next")
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Text(course?.short ?? next.lesson.courseID)
                    .fontWeight(.semibold)
                Text(TimetableText.until(next.start, now: now, calendar: calendar))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func courseColor(_ course: TimetableCourse?) -> Color {
        guard let course else { return DesignTokens.Palette.secondaryText }
        return Color(timetableHex: TimetableSchedule.colorHex(for: course, among: timetable.courses.map(\.id)))
    }
}

// MARK: - Week grid

private struct TimetableWeekGrid: View {
    @EnvironmentObject private var store: TimetableStore
    let timetable: Timetable
    let followed: Set<String>
    let now: Date
    let open: (String) -> Void

    private let calendar = Calendar.current
    private let hourColumnWidth: CGFloat = 20
    private let headerHeight: CGFloat = 16

    var body: some View {
        let lessons = timetable.lessons.filter { followed.contains($0.courseID) }
        let days = TimetableSchedule.visibleDays(for: lessons)
        let hours = TimetableSchedule.hourRange(for: lessons)
        let today = Weekday(date: now, calendar: calendar)

        GeometryReader { geo in
            let gridHeight = max(1, geo.size.height - headerHeight)
            let pointsPerMinute = gridHeight / CGFloat((hours.upperBound - hours.lowerBound) * 60)
            let columnWidth = (geo.size.width - hourColumnWidth) / CGFloat(days.count)
            let lanes = TimetableSchedule.lanes(for: lessons)

            ZStack(alignment: .topLeading) {
                // Hour lines + labels.
                ForEach(Array(hours), id: \.self) { hour in
                    let y = headerHeight + CGFloat((hour - hours.lowerBound) * 60) * pointsPerMinute
                    Rectangle()
                        .fill(DesignTokens.Palette.separator)
                        .frame(width: geo.size.width - hourColumnWidth, height: 0.5)
                        .offset(x: hourColumnWidth, y: y)
                    if hour < hours.upperBound {
                        Text("\(hour)")
                            .font(.system(size: 8.5))
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Palette.tertiaryText)
                            .offset(x: 0, y: y - 1)
                    }
                }

                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    let x = hourColumnWidth + CGFloat(index) * columnWidth
                    // Day header + today's tint.
                    Text(day.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(day == today ? DesignTokens.Palette.statusRunning
                                                      : DesignTokens.Palette.secondaryText)
                        .frame(width: columnWidth, height: headerHeight)
                        .offset(x: x)
                    if day == today {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignTokens.Palette.statusRunning.opacity(0.07))
                            .frame(width: columnWidth, height: gridHeight)
                            .offset(x: x, y: headerHeight)
                    }

                    ForEach(lessons.filter { $0.day == day }) { lesson in
                        let top = CGFloat(lesson.start.minutes - hours.lowerBound * 60) * pointsPerMinute
                        let height = CGFloat(lesson.end.minutes - lesson.start.minutes) * pointsPerMinute
                        let lane = lanes[lesson.id] ?? .init(index: 0, count: 1)
                        let laneWidth = columnWidth / CGFloat(lane.count)
                        block(lesson, day: day, height: height)
                            .frame(width: laneWidth - 3, height: max(10, height - 2))
                            .offset(x: x + CGFloat(lane.index) * laneWidth + 1.5, y: headerHeight + top + 1)
                    }
                }

                // "Now" line across today's column.
                if let index = days.firstIndex(of: today) {
                    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
                    if minutes >= hours.lowerBound * 60, minutes <= hours.upperBound * 60 {
                        Rectangle()
                            .fill(DesignTokens.Palette.statusFailure)
                            .frame(width: columnWidth, height: 1.5)
                            .offset(x: hourColumnWidth + CGFloat(index) * columnWidth,
                                    y: headerHeight + CGFloat(minutes - hours.lowerBound * 60) * pointsPerMinute)
                    }
                }
            }
        }
    }

    private func block(_ lesson: TimetableLesson, day: Weekday, height: CGFloat) -> some View {
        let course = timetable.course(id: lesson.courseID)
        let color = course.map {
            Color(timetableHex: TimetableSchedule.colorHex(for: $0, among: timetable.courses.map(\.id)))
        } ?? DesignTokens.Palette.secondaryText
        let hasNote = store.lessonNote(courseID: lesson.courseID, dayKey: dayKeyThisWeek(day)) != nil
        return Button { open(lesson.courseID) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(course?.short ?? lesson.courseID)
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                    if hasNote {
                        Circle().fill(Color.white).frame(width: 4, height: 4)
                    }
                }
                if height > 26 {
                    Text(lesson.start.text)
                        .font(.system(size: 8.5))
                        .monospacedDigit()
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(course?.name ?? lesson.courseID) · \(TimetableText.timeAndPlace(lesson, timetable: timetable))")
        .accessibilityLabel(Text("\(course?.name ?? lesson.courseID), \(day.shortLabel) \(lesson.start.text)"))
    }

    /// The date of `day` in the current Monday-based week.
    private func dayKeyThisWeek(_ day: Weekday) -> String {
        let today = Weekday(date: now, calendar: calendar)
        let date = calendar.date(byAdding: .day, value: day.isoIndex - today.isoIndex, to: now) ?? now
        return TimetableSchedule.dayKey(date, calendar: calendar)
    }
}

// MARK: - Shared bits

struct TimetableEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button("Open Timetable Settings") {
                SettingsWindowPresenter.shared.show(section: .timetable)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small text formatters shared by the Timetable views. Pure.
enum TimetableText {
    /// "10:00–12:00 · B2 · DIAG"
    static func timeAndPlace(_ lesson: TimetableLesson, timetable: Timetable) -> String {
        var parts = ["\(lesson.start.text)–\(lesson.end.text)"]
        if let room = lesson.room { parts.append(room) }
        if let location = timetable.location(id: lesson.locationID) { parts.append(location.name) }
        return parts.joined(separator: " · ")
    }

    /// "25 min", "1 h", "1 h 10"
    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }

    /// "in 25 min" within a day, otherwise "Thu 08:00".
    static func until(_ date: Date, now: Date, calendar: Calendar) -> String {
        let minutes = TimetableSchedule.minutes(from: now, to: date)
        if minutes < 12 * 60, calendar.isDate(date, inSameDayAs: now) {
            return "in \(duration(minutes: minutes))"
        }
        let day = Weekday(date: date, calendar: calendar).shortLabel
        let hm = ClockTime(minutes: calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        return "\(day) \(hm.text)"
    }

    /// "today", "tomorrow", "in 12 days", "3 days ago"
    static func countdown(days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case ..<0: return "\(-days) days ago"
        default: return "in \(days) days"
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color (falls back to grey for malformed input).
    init(timetableHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

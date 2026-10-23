import SwiftUI
import PDFKit

public enum TimetableColors {
    public static let palette = ["#8577FF", "#20C997", "#FF7A3D", "#F0588C", "#3BC9DB", "#FCC419",
                                 "#94D82D", "#E599F7", "#4DABF7", "#FF6B6B", "#A0785A", "#868E96"]
    public static func hex(for course: TimetableCourseData, in courses: [TimetableCourseData]) -> String {
        course.colorHex ?? palette[(courses.map(\.id).sorted().firstIndex(of: course.id) ?? 0) % palette.count]
    }
    public static func color(_ hex: String) -> Color {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x7464CC
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    public static func foreground(_ hex: String) -> Color {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x7464CC
        let brightness = (Double((value >> 16) & 255) * 0.2126 + Double((value >> 8) & 255) * 0.7152 + Double(value & 255) * 0.0722) / 255
        return brightness > 0.65 ? Color.black.opacity(0.88) : .white
    }
}

public enum TimetablePresentation: Equatable, Sendable {
    case automatic, today, compact, week, overview
}

public struct SharedTimetableView: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedTimetable>
    private let isEditing: Bool
    private let presentation: TimetablePresentation
    @State private var showEditor = false
    @State private var selected: TimetableLessonData?
    @State private var pdfPage = 0

    public init(channel: SharedWidgetChannel<SharedTimetable>, isEditing: Bool = false,
                presentation: TimetablePresentation = .automatic) {
        self.channel = channel; self.isEditing = isEditing; self.presentation = presentation
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: presentation == .compact ? 10 : 14) {
                    header
                    if let pdf = channel.value.pdf {
                        SharedTimetablePDFView(pdf: pdf, page: $pdfPage)
                    } else if let timetable = channel.value.timetable, !timetable.lessons.isEmpty {
                        if presentation == .today {
                            today(timetable, now: context.date)
                        } else {
                          HStack(spacing: 20) {
                            if (presentation == .overview || presentation == .automatic),
                               geometry.size.width >= (presentation == .overview ? 620 : 720),
                               geometry.size.height >= 300 {
                                today(timetable, now: context.date)
                                    .frame(width: min(230, geometry.size.width * 0.25))
                            }
                            weekGrid(timetable, now: context.date)
                                .overlay {
                                    if channel.value.followedLessons.isEmpty {
                                        Button("Scegli i corsi da mostrare…") { showEditor = true }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                          }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 35, weight: .light)).foregroundStyle(.cyan.opacity(0.8))
                            Text("La tua settimana, a colpo d’occhio").font(.system(size: 16, weight: .semibold))
                            Text("Importa un orario JSON, CSV o PDF.\nLo ritrovi anche in NotchDeck.")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                            Button("Importa orario…") { showEditor = true }
                                .buttonStyle(.borderedProminent).tint(.indigo)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let error = channel.errorMessage {
                        Label("Condivisione non disponibile: \(error)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                }
                .padding(presentation == .compact ? 12 : 18)
            }
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.18), Color(red: 0.035, green: 0.045, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showEditor) { SharedTimetableEditor(channel: channel) }
        .popover(item: $selected) { lesson in details(lesson).padding(18).frame(width: 290) }
        .onChange(of: channel.value.pdf?.name) { _, _ in pdfPage = 0 }
        .disabled(isEditing)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar").foregroundStyle(.cyan)
            Text(presentation == .today ? "Oggi" : (presentation == .compact ? "Orario" : (channel.value.pdf?.name ?? channel.value.timetable?.title ?? "Orario settimanale")))
                .font(.system(size: presentation == .compact ? 13 : 16, weight: .semibold, design: .rounded)).lineLimit(1)
                .help(channel.value.pdf?.name ?? channel.value.timetable?.title ?? "Orario settimanale")
            Spacer(minLength: 4)
            if presentation != .compact {
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .help("Dati condivisi tra LaunchPad e NotchDeck")
            }
            Button { showEditor = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 28, height: 26)
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
            .help("Importa e configura l’orario condiviso").accessibilityLabel("Configura orario condiviso")
        }
    }

    private func today(_ timetable: WeeklyTimetable, now: Date) -> some View {
        let current = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        let entries = channel.value.followedLessons.filter { $0.day == TimetableClock.today(now) }.sorted { $0.startMinute < $1.startMinute }
        return VStack(alignment: .leading, spacing: 10) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalized)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 3)
            if entries.isEmpty {
                Text("Nessuna lezione oggi").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 8) {
               ForEach(entries) { lesson in
                let course = timetable.courses.first { $0.id == lesson.courseID }
                let active = lesson.startMinute <= current && current < lesson.endMinute
                Button { selected = lesson } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Capsule().fill(course.map { TimetableColors.color(TimetableColors.hex(for: $0, in: timetable.courses)) } ?? .cyan)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(course?.name ?? lesson.courseID).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            Text("\(lesson.start)–\(lesson.end)\(lesson.room.map { " · " + $0 } ?? "")")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            if active {
                                Text("In corso · ancora \(lesson.endMinute - current) min")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                                ProgressView(value: Double(current - lesson.startMinute), total: Double(lesson.endMinute - lesson.startMinute)).tint(.cyan)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: active ? 78 : 48)
                    .padding(10)
                    .background(.white.opacity(active ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 12))
                    .opacity(lesson.endMinute <= current ? 0.5 : 1)
                }.buttonStyle(.plain)
               }
              }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
            if let next = nextLesson(now) {
                let course = timetable.courses.first { $0.id == next.courseID }
                Label("Prossima: \(dayLabel(next.day)) \(next.start) · \(course?.short ?? next.courseID)", systemImage: "arrow.right.circle")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
            }
        }
    }

    private func weekGrid(_ timetable: WeeklyTimetable, now: Date) -> some View {
        let lessons = channel.value.followedLessons
        let days = TimetableLayout.visibleDays(lessons)
        let startHour = (lessons.map(\.startMinute).min() ?? 480) / 60
        let endHour = max(startHour + 1, ((lessons.map(\.endMinute).max() ?? 1080) + 59) / 60)
        let lanes = TimetableLayout.lanes(lessons)
        let today = TimetableClock.today(now)
        let current = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        return GeometryReader { geometry in
            let gutter: CGFloat = 26
            let header: CGFloat = 24
            let height = max(1, geometry.size.height - header - 8)
            let column = max(1, (geometry.size.width - gutter) / CGFloat(days.count))
            let scale = height / CGFloat((endHour - startHour) * 60)
            ZStack(alignment: .topLeading) {
                ForEach(startHour...endHour, id: \.self) { hour in
                    let y = header + CGFloat((hour - startHour) * 60) * scale
                    Rectangle().fill(.white.opacity(0.065)).frame(width: geometry.size.width - gutter, height: 0.5)
                        .offset(x: gutter, y: y)
                    if hour < endHour {
                        Text(String(format: "%02d", hour)).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38)).offset(y: y - 4)
                    }
                }
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    let x = gutter + CGFloat(index) * column
                    Text(dayLabel(day)).font(.system(size: presentation == .compact ? 9 : 11, weight: .semibold))
                        .foregroundStyle(day == today ? .cyan : .white.opacity(0.55))
                        .frame(width: column, height: header - 4).offset(x: x)
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5, height: height).offset(x: x, y: header)
                    if day == today {
                        RoundedRectangle(cornerRadius: 7).fill(.cyan.opacity(0.04))
                            .frame(width: column, height: height).offset(x: x, y: header)
                    }
                    ForEach(lessons.filter { $0.day == day }) { lesson in
                        let lane = lanes[lesson.id] ?? TimetableLane(index: 0, count: 1)
                        let width = column / CGFloat(lane.count)
                        let blockHeight = max(5, CGFloat(lesson.endMinute - lesson.startMinute) * scale - 3)
                        let course = timetable.courses.first { $0.id == lesson.courseID }
                        let hex = course.map { TimetableColors.hex(for: $0, in: timetable.courses) } ?? "#7464CC"
                        Button { selected = lesson } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course?.short ?? lesson.courseID)
                                    .font(.system(size: min(13, max(presentation == .compact ? 8 : 9, width * 0.16)), weight: .bold)).lineLimit(1)
                                if blockHeight >= 30 {
                                    Text(presentation == .week && width >= 100 ? "\(lesson.start)–\(lesson.end)" : lesson.start)
                                        .font(.system(size: presentation == .compact ? 8 : 10, weight: .medium, design: .rounded)).lineLimit(1)
                                }
                                if presentation == .week, blockHeight >= 85, width >= 100, let course {
                                    Text(course.name).font(.system(size: 10)).lineLimit(2).opacity(0.9)
                                }
                                if presentation != .compact, blockHeight >= 63, width >= 70, let room = lesson.room {
                                    Text(room).font(.system(size: 9)).lineLimit(1).opacity(0.85)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(presentation == .compact ? 3 : min(7, max(3, blockHeight * 0.12)))
                            .frame(width: max(1, width - 4), height: blockHeight, alignment: .topLeading)
                            .foregroundStyle(TimetableColors.foreground(hex))
                            .background(TimetableColors.color(hex), in: RoundedRectangle(cornerRadius: 7))
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .offset(x: x + CGFloat(lane.index) * width + 2,
                                y: header + CGFloat(lesson.startMinute - startHour * 60) * scale + 1)
                        .help("\(course?.name ?? lesson.courseID) · \(lesson.start)–\(lesson.end)\(lesson.room.map { " · " + $0 } ?? "")")
                        .accessibilityLabel("\(dayLabel(day)), \(course?.name ?? lesson.courseID), \(lesson.start)–\(lesson.end)")
                    }
                    if day == today, current >= startHour * 60, current <= endHour * 60 {
                        Rectangle().fill(Color(red: 1, green: 0.38, blue: 0.42)).frame(width: column, height: 1.5)
                            .offset(x: x, y: header + CGFloat(current - startHour * 60) * scale)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func nextLesson(_ now: Date) -> TimetableLessonData? {
        let current = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        return TimetableLayout.nextLesson(channel.value.followedLessons, day: TimetableClock.today(now), minute: current)
    }
    private func details(_ lesson: TimetableLessonData) -> some View {
        let timetable = channel.value.timetable
        let course = timetable?.courses.first { $0.id == lesson.courseID }
        let location = timetable?.locations.first { $0.id == lesson.locationID }
        return VStack(alignment: .leading, spacing: 10) {
            Text(course?.name ?? lesson.courseID).font(.headline)
            Label("\(dayLabel(lesson.day)) · \(lesson.start)–\(lesson.end)", systemImage: "clock")
            if let room = lesson.room { Label(room, systemImage: "door.left.hand.open") }
            if let location { Label(location.name, systemImage: "mappin.and.ellipse") }
            if let professor = course?.professor { Text(professor).foregroundStyle(.secondary) }
            if let note = channel.value.userData[lesson.courseID]?.note, !note.isEmpty {
                Divider(); Text(note).textSelection(.enabled)
            }
        }.font(.callout)
    }
    private func dayLabel(_ day: String) -> String {
        ["mon":"Lun", "tue":"Mar", "wed":"Mer", "thu":"Gio", "fri":"Ven", "sat":"Sab", "sun":"Dom"][day] ?? day
    }
}

public struct SharedTimetablePDFView: View {
    public let pdf: TimetablePDF
    @Binding public var page: Int
    @State private var document: PDFDocument?
    @State private var image: NSImage?
    public init(pdf: TimetablePDF, page: Binding<Int>) { self.pdf = pdf; _page = page }
    public var body: some View {
        VStack(spacing: 8) {
            if let document, document.pageCount > 0 {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if document.pageCount > 1 {
                    HStack {
                        Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page <= 0)
                        Text("Pagina \(min(page + 1, document.pageCount)) di \(document.pageCount)").font(.caption)
                        Button { page = min(document.pageCount - 1, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page + 1 >= document.pageCount)
                    }.buttonStyle(.borderless)
                }
            } else { Text("Caricamento documento…").font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: pdf.data) {
            document = PDFDocument(data: pdf.data)
            renderPage()
        }
        .onChange(of: page) { _, _ in renderPage() }
    }
    private func renderPage() {
        guard let document, document.pageCount > 0 else { image = nil; return }
        let selected = min(max(0, page), document.pageCount - 1)
        if selected != page { page = selected }
        image = document.page(at: selected)?.thumbnail(of: CGSize(width: 1600, height: 1200), for: .mediaBox)
    }
}

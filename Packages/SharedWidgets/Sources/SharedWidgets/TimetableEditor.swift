import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

public struct SharedTimetableEditor: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedTimetable>
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var format = "json"
    @State private var candidate: WeeklyTimetable?
    @State private var candidatePDF: TimetablePDF?
    @State private var sourceName = ""
    @State private var message: String?
    @State private var pdfPage = 0
    @State private var showRemove = false

    public init(channel: SharedWidgetChannel<SharedTimetable>) { self.channel = channel }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Orario condiviso").font(.title2.weight(.semibold))
                    Text("Le modifiche compaiono in LaunchPad e NotchDeck su questo Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Chiudi") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button("Importa JSON, CSV o PDF…", action: chooseFile)
                        Menu("Scarica modello") {
                            Button("JSON") { export(TimetableImporter.exampleJSON, name: "orario.json", type: .json) }
                            Button("CSV") { export(TimetableImporter.exampleCSV, name: "orario.csv", type: .commaSeparatedText) }
                        }
                        Spacer()
                    }
                    Text("JSON e CSV diventano una griglia interattiva. I PDF vengono mostrati come documento originale, anche se sono scansioni; non vengono convertiti automaticamente in lezioni.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    GroupBox("Incolla o modifica i dati") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("Formato", selection: $format) {
                                    Text("JSON").tag("json"); Text("CSV").tag("csv")
                                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                                    .accessibilityLabel("Formato dati")
                                Spacer()
                                Button("Esempio") {
                                    text = format == "json" ? TimetableImporter.exampleJSON : TimetableImporter.exampleCSV
                                    validate()
                                }
                            }
                            WidgetTextEditor(text: Binding(get: { text }, set: {
                                text = $0; candidate = nil; candidatePDF = nil
                            }), ink: .white, paper: NSColor(white: 0.1, alpha: 1), font: .monospacedSystemFont(ofSize: 11, weight: .regular))
                                .frame(height: 125)
                                .accessibilityLabel("Dati dell’orario")
                            HStack {
                                Text("CSV: giorno, inizio, fine, titolo; opzionali sigla, colore, aula, sede.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Verifica dati", action: validate).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }.padding(6)
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let timetable = candidate {
                        GroupBox("Anteprima: \(timetable.courses.count) corsi · \(timetable.lessons.count) lezioni") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(timetable.lessons.prefix(12))) { lesson in
                                    HStack {
                                        Text(lesson.day.uppercased()).frame(width: 35, alignment: .leading)
                                        Text("\(lesson.start)–\(lesson.end)").monospacedDigit().frame(width: 105, alignment: .leading)
                                        Text(timetable.courses.first { $0.id == lesson.courseID }?.name ?? lesson.courseID)
                                        Spacer()
                                        Text(lesson.room ?? "").foregroundStyle(.secondary)
                                    }.font(.system(size: 11)).lineLimit(1)
                                }
                                if timetable.lessons.count > 12 { Text("…altre \(timetable.lessons.count - 12) lezioni").font(.caption).foregroundStyle(.secondary) }
                            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let pdf = candidatePDF {
                        GroupBox("Anteprima PDF: \(pdf.name)") {
                            SharedTimetablePDFView(pdf: pdf, page: $pdfPage).frame(height: 180)
                        }
                    }
                    if let current = channel.value.timetable {
                        GroupBox("Corsi da mostrare") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(current.courses) { course in
                                    Toggle(isOn: Binding(
                                        get: { channel.value.userData[course.id]?.followed ?? true },
                                        set: { enabled in
                                            do {
                                                try channel.update { value in
                                                    var state = value.userData[course.id] ?? TimetableCourseState(followed: true)
                                                    state.followed = enabled; value.userData[course.id] = state
                                                }
                                            } catch { message = error.localizedDescription }
                                        }
                                    )) {
                                        HStack(spacing: 7) {
                                            Circle().fill(TimetableColors.color(TimetableColors.hex(for: course, in: current.courses))).frame(width: 7, height: 7)
                                            Text(course.short).fontWeight(.semibold)
                                            Text(course.name).foregroundStyle(.secondary).lineLimit(1)
                                        }.font(.system(size: 12))
                                    }.toggleStyle(.checkbox)
                                }
                            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if channel.value.pdf != nil, channel.value.timetable != nil {
                        Button("Mostra di nuovo la griglia interattiva") {
                            do { try channel.update { $0.pdf = nil } } catch { message = error.localizedDescription }
                        }
                    }
                    if channel.value.pdf != nil || channel.value.timetable != nil {
                        Button("Rimuovi orario da entrambe le app…", role: .destructive) { showRemove = true }
                    }
                }
                .padding(.trailing, 6)
            }
            HStack {
                if !sourceName.isEmpty { Text(sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button("Applica orario") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(candidate == nil && candidatePDF == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 710, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let current = channel.value.timetable,
               let data = try? prettyEncoder().encode(current) { text = String(decoding: data, as: UTF8.self) }
        }
        .confirmationDialog("Rimuovere l’orario condiviso?", isPresented: $showRemove) {
            Button("Rimuovi orario", role: .destructive) {
                do { try channel.update { $0.timetable = nil; $0.pdf = nil }; dismiss() }
                catch { message = error.localizedDescription }
            }
        } message: { Text("Le note dei corsi e gli esami rimangono salvati per una successiva importazione.") }
    }

    private func validate() {
        candidate = nil; candidatePDF = nil; message = nil
        do {
            candidate = try format == "json" ? TimetableImporter.json(Data(text.utf8)) : TimetableImporter.csv(text)
        } catch { message = error.localizedDescription }
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText, .tabSeparatedText, .pdf, .plainText]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        let read: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            importFile(url)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: read) }
        else { read(panel.runModal()) }
    }
    private func importFile(_ url: URL) {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw TimetableImportError("Scegli un file più piccolo di 20 MB.") }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "pdf" {
                guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0, pdf.pageCount <= 100 else {
                    throw TimetableImportError("Il PDF deve essere leggibile, senza password e con al massimo 100 pagine.")
                }
                candidate = nil; candidatePDF = TimetablePDF(name: url.lastPathComponent, data: data); pdfPage = 0
            } else {
                guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .windowsCP1252) else {
                    throw TimetableImportError("La codifica del testo non è riconosciuta. Esporta il file come UTF-8.")
                }
                format = url.pathExtension.lowercased() == "json" ? "json" : "csv"
                text = value
                validate()
            }
            sourceName = url.lastPathComponent; message = nil
        } catch { message = error.localizedDescription }
    }
    private func apply() {
        do {
            if let candidate { try channel.update { $0.install(candidate) } }
            else if let candidatePDF { try channel.update { $0.pdf = candidatePDF } }
            else { return }
            dismiss()
        } catch { message = error.localizedDescription }
    }
    private func export(_ value: String, name: String, type: UTType) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try value.write(to: url, atomically: true, encoding: .utf8) }
            catch { message = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: save) }
        else { save(panel.runModal()) }
    }
    private func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}

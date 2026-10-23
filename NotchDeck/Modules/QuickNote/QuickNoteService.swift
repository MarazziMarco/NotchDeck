import Foundation
import Combine
import SharedWidgets

/// One note shared locally with LaunchPad; isolated file names remain independent for tests.
@MainActor
final class QuickNoteService: ObservableObject {
    @Published var title = "" { didSet { if title != oldValue { saveTitle() } } }
    @Published var text: String { didSet { scheduleSave() } }
    @Published private(set) var sharingError: String?
    private let store: JSONFileStore<String>
    private var saveWork: DispatchWorkItem?
    private var sharedChannel: SharedWidgetChannel<SharedNote>?
    private var sharingObserver: AnyCancellable?
    private var receivingSharedValue = false

    init(fileName: String = "quick-note.json", sharedChannel: SharedWidgetChannel<SharedNote>? = nil, fileURL: URL? = nil) {
        store = fileURL.map { JSONFileStore(url: $0) } ?? JSONFileStore(fileName: fileName)
        text = store.load() ?? ""
        if let channel = sharedChannel ?? (fileName == "quick-note.json" && fileURL == nil ? SharedWidgetLibrary.shared.note : nil) {
            self.sharedChannel = channel
            sharingObserver = channel.$value.sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.receivingSharedValue = true
                    if self.text != note.text {
                        self.text = note.text
                        self.store.save(note.text)
                    }
                    if note.title != self.title {
                        self.title = SharedNote.editableTitle(note.title)
                    }
                    self.receivingSharedValue = false
                }
            }
        }
    }

    private func saveTitle() {
        guard !receivingSharedValue, let channel = sharedChannel else { return }
        do { try channel.update { $0.title = title }; sharingError = nil }
        catch { sharingError = error.localizedDescription }
    }

    private func scheduleSave() {
        guard !receivingSharedValue else { return }
        if let channel = sharedChannel {
            let edited = text
            do {
                try channel.update { $0.text = edited }
                store.save(edited)
                sharingError = nil
            } catch { sharingError = error.localizedDescription }
            return
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.save(self.text)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var firstLine: String { text.split(separator: "\n").first.map(String.init) ?? "" }
    var wordCount: Int { text.split { $0 == " " || $0 == "\n" }.count }
}

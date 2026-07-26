import Foundation
import Combine

/// A single local, temporary scratch note. Persisted locally only — no cloud.
@MainActor
final class QuickNoteService: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }

    private let store: JSONFileStore<String>
    private var saveWork: DispatchWorkItem?

    init(fileName: String = "quick-note.json") {
        self.store = JSONFileStore(fileName: fileName)
        self.text = store.load() ?? ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.save(self.text)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var firstLine: String {
        text.split(separator: "\n").first.map(String.init) ?? ""
    }
    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }
}

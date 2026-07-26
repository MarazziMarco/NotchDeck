import Foundation

/// Persists clipboard history locally. Thin wrapper over `JSONFileStore` so the
/// service can be initialised with an in-memory double in tests.
struct ClipboardPersistence {
    private let store: JSONFileStore<ClipboardHistory>

    init(fileName: String = "clipboard-history.json") {
        self.store = JSONFileStore(fileName: fileName)
    }
    init(url: URL) {
        self.store = JSONFileStore(url: url)
    }

    func load() -> ClipboardHistory? { store.load() }
    func save(_ history: ClipboardHistory) { store.save(history) }
    func clear() { store.delete() }
}

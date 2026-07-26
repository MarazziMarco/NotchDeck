import Foundation

/// Resolves and creates NotchDeck's local storage locations. Everything stays
/// under Application Support — no cloud, no sync.
enum AppPaths {
    static let bundleFolderName = "NotchDeck"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(bundleFolderName, isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    static var logsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Logs", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    static func file(_ name: String) -> URL {
        supportDirectory.appendingPathComponent(name)
    }

    static func ensureDirectory(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url,
                                                     withIntermediateDirectories: true)
        }
    }
}

/// Small typed JSON file store used by several modules.
struct JSONFileStore<Value: Codable> {
    let url: URL
    init(fileName: String) { self.url = AppPaths.file(fileName) }
    init(url: URL) { self.url = url }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func delete() { try? FileManager.default.removeItem(at: url) }
}

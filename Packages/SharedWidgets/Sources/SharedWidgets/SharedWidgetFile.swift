import Foundation
import Combine
import Darwin

/// Both apps use this location; installation and removal of either app do not own the data.
public enum SharedWidgetPaths {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarazziWidgets", isDirectory: true)
    }
}

public struct SharedWidgetFile<Value: Codable & Equatable & Sendable>: Sendable {
    public let url: URL
    public init(key: String, directory: URL = SharedWidgetPaths.directory) {
        precondition(!key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        url = directory.appendingPathComponent(key + ".json")
    }
    public var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }

    public func read() throws -> Value? {
        if !FileManager.default.fileExists(atPath: url.path),
           !FileManager.default.fileExists(atPath: backupURL.path) { return nil }
        do { return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) }
        catch {
            if let data = try? Data(contentsOf: backupURL), let value = try? JSONDecoder().decode(Value.self, from: data) {
                return value
            }
            throw error
        }
    }

    /// Re-read inside a process-shared lock before applying a mutation. A stale app never
    /// overwrites unrelated changes made by the other app in the meantime.
    @discardableResult
    public func update(default initial: Value, _ change: (inout Value) throws -> Void) throws -> Value {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        let previous = try read()
        var next = previous ?? initial
        try change(&next)
        if next != previous || !FileManager.default.fileExists(atPath: url.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            // Commit the backup first, so an interruption always leaves a readable version.
            try data.write(to: backupURL, options: .atomic)
            try data.write(to: url, options: .atomic)
        }
        return next
    }
}

@MainActor
public final class SharedWidgetChannel<Value: Codable & Equatable & Sendable>: ObservableObject {
    @Published public private(set) var value: Value
    @Published public private(set) var errorMessage: String?
    private let file: SharedWidgetFile<Value>
    private var timer: Timer?
    private var signature: String?

    public init(key: String, initial: Value, directory: URL = SharedWidgetPaths.directory, observe: Bool = true) {
        file = SharedWidgetFile(key: key, directory: directory)
        value = initial
        do { value = try file.update(default: initial) { _ in } }
        catch { errorMessage = error.localizedDescription }
        signature = fileSignature()
        if observe {
            let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    public func update(_ change: (inout Value) throws -> Void) throws {
        do {
            let next = try file.update(default: value, change)
            if next != value { value = next }
            errorMessage = nil
            signature = fileSignature()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func refresh() {
        let current = fileSignature()
        guard current != signature else { return }
        do {
            if let next = try file.read(), next != value { value = next }
            signature = current
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func stopObserving() { timer?.invalidate(); timer = nil }

    private func fileSignature() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path) else { return nil }
        return "\(attributes[.modificationDate] ?? ""):\(attributes[.systemFileNumber] ?? ""):\(attributes[.size] ?? "")"
    }
    deinit { timer?.invalidate() }
}

public struct SharedNote: Codable, Equatable, Sendable {
    public var title = "Nota"
    public var text = ""
    public var color = "yellow"
    public var migratedSources: Set<String> = []
    public init() {}

    /// Keep both pre-existing notes when first connecting two previously separate apps.
    public mutating func migrate(source: String, title: String = "Nota", text: String, color: String = "yellow") {
        guard migratedSources.insert(source).inserted else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if self.text.isEmpty {
            self.title = title; self.text = text; self.color = color
        } else if self.text != text {
            self.text += "\n\n— Importata da \(source) —\n" + text
        }
    }
}

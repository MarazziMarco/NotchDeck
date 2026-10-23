import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

public struct SharedShelfItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var intakeMode: String
    public var originalPath: String
    public var stagedPath: String?
    public var bookmark: Data?
    public var byteSize: Int64
    public var typeIdentifier: String?
    public var addedAt: Date
    public var transferState: String
    public var recovered: Bool
    public init(reference: URL, staged: URL? = nil) {
        id = UUID(); name = reference.lastPathComponent; originalPath = reference.path
        stagedPath = staged?.path; intakeMode = staged == nil ? "keepOriginalReference" : "moveIntoShelf"
        transferState = staged == nil ? "referenced" : "staged"
        bookmark = staged == nil ? try? reference.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        let attributes = try? reference.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        byteSize = Int64(attributes?.fileSize ?? 0); typeIdentifier = attributes?.contentType?.identifier
        addedAt = .now; recovered = false
    }
    public var isReference: Bool { intakeMode == "keepOriginalReference" }
    public func resolveURL() -> URL? {
        if !isReference {
            guard let stagedPath, FileManager.default.fileExists(atPath: stagedPath) else { return nil }
            return URL(fileURLWithPath: stagedPath)
        }
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale), FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.fileExists(atPath: originalPath) ? URL(fileURLWithPath: originalPath) : nil
    }
}
public struct ShelfPreferences: Codable, Equatable, Sendable {
    public var copyIntoShelf = false
    public var newestFirst = true
    public var showFileSize = true
    public init() {}
}
public struct SharedShelf: Codable, Equatable, Sendable {
    public var items: [SharedShelfItem] = []
    public var preferences = ShelfPreferences()
    public var migratedLegacy = false
    public init() {}
    public mutating func add(_ item: SharedShelfItem) {
        guard !items.contains(where: { $0.originalPath == item.originalPath || (item.stagedPath != nil && $0.stagedPath == item.stagedPath) }) else { return }
        items.insert(item, at: 0)
    }
    /// Apply only the native shelf's delta, so another app's additions and removals survive.
    public mutating func merge(local: [SharedShelfItem], baseline: [SharedShelfItem]) {
        let deleted = Set(baseline.map(\.id)).subtracting(local.map(\.id))
        items.removeAll { deleted.contains($0.id) }
        for item in local where baseline.first(where: { $0.id == item.id }) != item {
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
            else { add(item) }
        }
    }
}

@MainActor public final class SharedShelfController: ObservableObject {
    public let channel: SharedWidgetChannel<SharedShelf>
    public let stagingDirectory: URL
    @Published public private(set) var isAdding = false
    @Published public private(set) var errorMessage: String?
    public init(channel: SharedWidgetChannel<SharedShelf>, directory: URL) {
        self.channel = channel; stagingDirectory = directory.appendingPathComponent("FileShelf", isDirectory: true)
        recoverStoredFiles()
    }
    /// Recover committed copies after an interrupted metadata save; never scans user folders.
    public func recoverStoredFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        do {
            try channel.update { state in
                let known = Set(state.items.compactMap { $0.stagedPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } })
                for url in files where url.lastPathComponent != "manifest.json" && !known.contains(url.resolvingSymlinksInPath().path) {
                    var item = SharedShelfItem(reference: url, staged: url)
                    if let separator = url.lastPathComponent.range(of: "--") { item.name = String(url.lastPathComponent[separator.upperBound...]) }
                    item.recovered = true
                    state.add(item)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    public func add(_ urls: [URL]) async {
        guard !isAdding else { return }
        isAdding = true; errorMessage = nil
        defer { isAdding = false }
        let copy = channel.value.preferences.copyIntoShelf
        let root = stagingDirectory
        for url in urls where url.isFileURL {
            guard !channel.value.items.contains(where: { $0.originalPath == url.path || $0.stagedPath == url.path }) else { continue }
            do {
                let item = try await Task.detached(priority: .userInitiated) {
                    guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
                    if !copy { return SharedShelfItem(reference: url) }
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let incoming = root.appendingPathComponent(".incoming-" + UUID().uuidString)
                    let destination = root.appendingPathComponent(UUID().uuidString + "--" + url.lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: url, to: incoming)
                        try FileManager.default.moveItem(at: incoming, to: destination)
                    } catch {
                        try? FileManager.default.removeItem(at: incoming)
                        throw error
                    }
                    return SharedShelfItem(reference: url, staged: destination)
                }.value
                try channel.update { $0.add(item) }
            } catch { errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }
    public func remove(_ id: UUID) throws {
        channel.refresh()
        guard let item = channel.value.items.first(where: { $0.id == id }) else { return }
        if !item.isReference, let url = item.resolveURL() {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        }
        try channel.update { $0.items.removeAll { $0.id == id } }
    }
    public func chooseFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        let receive: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK else { return }
            Task { @MainActor in await self?.add(panel.urls) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: receive) }
        else { receive(panel.runModal()) }
    }
}

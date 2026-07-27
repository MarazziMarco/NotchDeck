import AppKit
import UniformTypeIdentifiers

/// A file or folder parked on the shelf. Two intake modes:
/// - `moveIntoShelf`: physically moved into the persistent staging area; we keep
///   its staged path plus the original location (for Restore).
/// - `keepOriginalReference`: original stays where it is; we keep a
///   security-scoped bookmark so access survives relaunch.
struct FileShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String                     // original filename
    var intakeMode: FileShelfIntakeMode
    var originalPath: String             // where it came from
    var stagedPath: String?              // location inside the shelf (move mode)
    var bookmark: Data?                  // reference-mode bookmark
    var byteSize: Int64
    var typeIdentifier: String?
    var addedAt: Date
    var transferState: FileShelfTransferState
    /// True when this entry was reconstructed from a staging file that was missing
    /// from the manifest (orphan recovery).
    var recovered: Bool = false

    /// Reference intake — original stays in place.
    init(id: UUID = UUID(), reference url: URL) {
        self.id = id
        self.name = url.lastPathComponent
        self.intakeMode = .keepOriginalReference
        self.originalPath = url.path
        self.stagedPath = nil
        self.addedAt = Date()
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .totalFileSizeKey])
        self.byteSize = Int64(v?.totalFileSize ?? v?.fileSize ?? 0)
        self.typeIdentifier = v?.contentType?.identifier
        self.bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
        self.transferState = .referenced
    }

    /// Move intake — physically staged inside the shelf.
    init(id: UUID = UUID(), staged: URL, original: URL) {
        self.id = id
        self.name = original.lastPathComponent
        self.intakeMode = .moveIntoShelf
        self.originalPath = original.path
        self.stagedPath = staged.path
        self.addedAt = Date()
        let v = try? staged.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .totalFileSizeKey])
        self.byteSize = Int64(v?.totalFileSize ?? v?.fileSize ?? 0)
        self.typeIdentifier = v?.contentType?.identifier
        self.bookmark = nil
        self.transferState = .staged
    }

    /// Resolve the current on-disk URL. Returns nil only when the item is
    /// genuinely gone.
    func resolveURL() -> URL? {
        switch intakeMode {
        case .moveIntoShelf:
            guard let stagedPath else { return nil }
            let u = URL(fileURLWithPath: stagedPath)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        case .keepOriginalReference:
            if let bookmark {
                var stale = false
                if let u = try? URL(resolvingBookmarkData: bookmark,
                                    options: [.withSecurityScope], relativeTo: nil,
                                    bookmarkDataIsStale: &stale) { return u }
            }
            let f = URL(fileURLWithPath: originalPath)
            return FileManager.default.fileExists(atPath: f.path) ? f : nil
        }
    }

    var isMissing: Bool { resolveURL() == nil }

    /// Path used for the workspace icon / help tooltip.
    var path: String { resolveURL()?.path ?? stagedPath ?? originalPath }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }

    /// One-shot storage hint shown in the UI.
    var storageLabel: String {
        intakeMode == .moveIntoShelf ? "Stored in Shelf" : "Linked from original location"
    }

    var originalLocationURL: URL { URL(fileURLWithPath: originalPath) }
    var originalLocationExists: Bool {
        FileManager.default.fileExists(atPath: originalLocationURL.deletingLastPathComponent().path)
    }
}

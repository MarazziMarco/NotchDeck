import Foundation

/// How File Shelf takes an item in when it is dropped.
enum FileShelfIntakeMode: String, Codable, CaseIterable, Identifiable {
    /// Physically move the file/folder into the persistent shelf staging area. It
    /// disappears from its original location and is safely stored until placed
    /// somewhere else.
    case moveIntoShelf
    /// Leave the original in place and store only a reference/bookmark.
    case keepOriginalReference
    var id: String { rawValue }
    var label: String {
        switch self {
        case .moveIntoShelf: return "Move into Shelf"
        case .keepOriginalReference: return "Keep original in place"
        }
    }
}

/// For `keepOriginalReference` items: when the reference is removed after a
/// drag-out.
enum FileShelfRetentionPolicy: String, Codable, CaseIterable, Identifiable {
    case removeAfterSuccessfulDrag
    case keepUntilRemoved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .removeAfterSuccessfulDrag: return "Remove after use"
        case .keepUntilRemoved: return "Keep items until manually removed"
        }
    }
}

/// Lifecycle state of a shelved item.
enum FileShelfTransferState: String, Codable, Equatable {
    case referenced      // reference-mode: original in place
    case staged          // move-mode: living in the shelf staging area
    case transferring    // mid staging copy
    case failed
}

enum FileShelfError: LocalizedError, Equatable {
    case originalMissing
    case verificationFailed
    case copyFailed(String)
    var errorDescription: String? {
        switch self {
        case .originalMissing: return "The original item no longer exists."
        case .verificationFailed: return "The staged copy could not be verified."
        case .copyFailed(let m): return "Copy failed: \(m)"
        }
    }
}

/// Owns the persistent File Shelf staging directory and performs crash-safe,
/// cross-volume-safe transactional moves. Pure file-system logic — no UI, no
/// main-actor state — so it is fully unit-testable with an injected root.
///
/// Persistent location (never a purgeable cache or temp dir):
///   ~/Library/Application Support/NotchDeck/FileShelf/
struct FileShelfStaging {
    let root: URL

    static var defaultRoot: URL {
        let dir = AppPaths.supportDirectory.appendingPathComponent("FileShelf", isDirectory: true)
        AppPaths.ensureDirectory(dir)
        return dir
    }

    init(root: URL = FileShelfStaging.defaultRoot) {
        self.root = root
        AppPaths.ensureDirectory(root)
    }

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }

    /// Transactional intake for move-mode:
    ///   1. copy to an incomplete temporary path inside the shelf;
    ///   2. verify the copy completed;
    ///   3. atomically rename to the final staged name (same-volume);
    ///   4. only then remove the original;
    ///   5. (manifest is updated by the caller after this commits).
    /// On any failure the original is preserved and incomplete staging data is
    /// cleaned up — the user is never left with neither copy.
    func stage(_ original: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: original.path) else { throw FileShelfError.originalMissing }

        let incoming = root.appendingPathComponent(".incoming-\(UUID().uuidString)")
        let final = uniqueDestination(for: original.lastPathComponent)
        do {
            try fm.copyItem(at: original, to: incoming)          // 1
            guard verify(original: original, copy: incoming) else { // 2
                throw FileShelfError.verificationFailed
            }
            try fm.moveItem(at: incoming, to: final)             // 3 (atomic rename, same volume)
        } catch {
            try? fm.removeItem(at: incoming)                     // clean incomplete data
            try? fm.removeItem(at: final)
            throw error                                          // original preserved
        }
        // 4 — copy committed & verified; now it is safe to remove the source.
        // Best-effort: the staged copy already exists, so a failed removal never
        // loses data (worst case a harmless duplicate remains).
        try? fm.removeItem(at: original)
        return final
    }

    /// Verify a copy: presence for directories; presence + matching byte size for
    /// files.
    func verify(original: URL, copy: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: copy.path) else { return false }
        var isDir: ObjCBool = false
        _ = fm.fileExists(atPath: original.path, isDirectory: &isDir)
        if isDir.boolValue { return true }
        let a = (try? original.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let b = (try? copy.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return a != nil && a == b
    }

    /// A non-colliding destination inside the shelf for `name`.
    func uniqueDestination(for name: String) -> URL {
        unique(in: root, name: name)
    }

    private func unique(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            i += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Real staged files on disk (excludes the manifest and incomplete temp copies).
    /// Used by orphan reconciliation — never deletes anything.
    func stagedFilesOnDisk() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.filter {
            let n = $0.lastPathComponent
            return n != "manifest.json" && !n.hasPrefix(".incoming-")
        }
    }

    func removeStaged(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    func moveToTrash(_ url: URL) throws {
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
    }

    /// Move a staged item to `destination` (used by Restore / Move to…). Returns
    /// the final URL. Non-colliding within the destination directory.
    @discardableResult
    func moveOut(_ staged: URL, to destination: URL) throws -> URL {
        let fm = FileManager.default
        let dir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = unique(in: dir, name: destination.lastPathComponent)
        try fm.moveItem(at: staged, to: target)
        return target
    }
}

import AppKit
import Combine

/// Holds shelved items and drives the staging engine. Move-mode items are
/// physically stored in the persistent shelf directory and survive relaunch;
/// reference-mode items keep only a bookmark to the untouched original.
@MainActor
final class FileShelfStore: ObservableObject {
    @Published private(set) var items: [FileShelfItem] = []
    @Published var lastError: String?
    /// True while a (potentially large) staging copy is in progress.
    @Published private(set) var isStaging = false
    /// Drives the one-time move-mode explainer banner.
    @Published var needsMoveExplainer = false

    /// Legacy TTL retention — applies to reference items only (staged files are
    /// never auto-expired, that would destroy the only copy).
    var retention: FileShelfRetention = .untilRemoved
    var intakeMode: FileShelfIntakeMode = .moveIntoShelf
    var retentionPolicy: FileShelfRetentionPolicy = .removeAfterSuccessfulDrag
    /// Set from settings so the store can raise the one-time explainer.
    var moveExplained = false

    private let engine: FileShelfStaging
    private let manifest: JSONFileStore<[FileShelfItem]>

    @Published private(set) var recoveredCount = 0

    init(engine: FileShelfStaging = FileShelfStaging()) {
        self.engine = engine
        self.manifest = JSONFileStore(url: engine.manifestURL)
        self.items = manifest.load() ?? []
        reconcile()
        recoverOrphansAtStartup()
        pruneExpired()
    }

    // MARK: Orphan reconciliation / recovery

    struct ShelfReconciliation: Equatable {
        var manifestPath: String
        var stagingPath: String
        var manifestEntries: [String]     // staged file names referenced by the manifest
        var filesOnDisk: [String]         // staged file names present on disk
        var orphanURLs: [String]          // on disk but NOT in the manifest
        var missingEntryIDs: [UUID]       // manifest entries whose file is gone
    }

    /// Compare the manifest to the real staging directory. Read-only — never
    /// deletes a disk file.
    func reconcileReport() -> ShelfReconciliation {
        let staged = items.filter { $0.intakeMode == .moveIntoShelf }
        let known = Set(staged.compactMap { $0.stagedPath.map(canonical) })
        let onDisk = engine.stagedFilesOnDisk()
        let orphans = onDisk.filter { !known.contains(canonical($0.path)) }
        let missing = staged.filter { !FileManager.default.fileExists(atPath: $0.stagedPath ?? "") }
        return ShelfReconciliation(
            manifestPath: engine.manifestURL.path,
            stagingPath: engine.root.path,
            manifestEntries: staged.compactMap { $0.stagedPath.map { ($0 as NSString).lastPathComponent } },
            filesOnDisk: onDisk.map(\.lastPathComponent),
            orphanURLs: orphans.map(\.lastPathComponent),
            missingEntryIDs: missing.map(\.id))
    }

    /// Recover staging files missing from the manifest by re-adding them to the
    /// shelf. Never deletes anything; never scans folders outside the shelf.
    /// Canonical path (resolves /var → /private/var and `..`) so manifest entries
    /// and on-disk enumeration compare correctly.
    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    @discardableResult
    func recoverMissingItems() -> Int {
        let known = Set(items.compactMap { $0.stagedPath.map(canonical) })
        var added = 0
        for url in engine.stagedFilesOnDisk() where !known.contains(canonical(url.path)) {
            var item = FileShelfItem(staged: url, original: url)
            item.recovered = true
            items.insert(item, at: 0)
            added += 1
        }
        if added > 0 { recoveredCount += added; persist() }
        return added
    }

    /// Auto-recover unambiguous orphans on startup (fixes files that vanished from
    /// the manifest). Safe: only re-adds, never deletes.
    private func recoverOrphansAtStartup() {
        _ = recoverMissingItems()
    }

    // MARK: Intake

    /// Add dropped URLs. Move-mode performs a transactional stage; reference-mode
    /// stores a bookmark. Duplicates (by original or staged path) are skipped.
    @discardableResult
    func add(urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            let path = url.path
            guard !items.contains(where: { $0.originalPath == path || $0.stagedPath == path }) else { continue }
            do {
                let item = try intake(url)
                items.insert(item, at: 0)
                added += 1
                if item.intakeMode == .moveIntoShelf && !moveExplained { needsMoveExplainer = true }
            } catch {
                lastError = "Couldn't add “\(url.lastPathComponent)”: \(error.localizedDescription)"
            }
        }
        if added > 0 { persist() }
        return added
    }

    private func intake(_ url: URL) throws -> FileShelfItem {
        switch intakeMode {
        case .keepOriginalReference:
            return FileShelfItem(reference: url)
        case .moveIntoShelf:
            isStaging = true
            defer { isStaging = false }
            let staged = try engine.stage(url)          // transactional, cross-volume safe
            return FileShelfItem(staged: staged, original: url)
        }
    }

    // MARK: Drag-out completion (real AppKit result)

    /// Called by the drag source with the genuine `NSDragOperation`. Transactional
    /// and non-destructive: the item is NEVER removed at drag start and a manifest
    /// change is committed only after a confirmed transfer.
    ///
    /// - none/cancelled/internal drop-back → no-op (keep everything).
    /// - copy → the destination has a copy; the shelf item REMAINS (staged file is
    ///   never deleted on a copy).
    /// - move → remove the shelf entry ONLY when the staged file has actually left
    ///   the shelf (the OS confirmed the move). A failed/internal "move" that
    ///   leaves the staged file in place is a no-op.
    func completeDrag(item: FileShelfItem, operation: NSDragOperation) {
        completeGroupDrag(items: [item.id], operation: operation)
    }

    /// Group-aware completion. Applies the transactional rule per item so a
    /// partial move removes only the items whose move actually completed.
    @discardableResult
    func completeGroupDrag(items ids: [UUID], operation: NSDragOperation) -> (removed: Int, kept: Int) {
        if operation.isEmpty { return (0, ids.count) }   // cancel / none / internal → keep all
        var removed = 0, kept = 0
        for id in ids {
            guard let idx = items.firstIndex(where: { $0.id == id }) else { continue }
            let it = items[idx]
            switch it.intakeMode {
            case .moveIntoShelf:
                if operation.contains(.move), it.resolveURL() == nil {
                    // The staged file genuinely left the shelf → commit removal.
                    items.removeAll { $0.id == id }; removed += 1
                } else {
                    kept += 1                            // copy, or move that didn't take → keep
                }
            case .keepOriginalReference:
                // The original file is owned by the user and never touched by us.
                // On a confirmed copy/move, honour the retention policy (removes the
                // REFERENCE only, never the file).
                if !operation.isEmpty, retentionPolicy == .removeAfterSuccessfulDrag {
                    items.removeAll { $0.id == id }; removed += 1
                } else { kept += 1 }
            }
        }
        if removed > 0 { persist() }
        return (removed, kept)
    }

    // MARK: Explicit actions

    /// Reference item → drop the reference (original untouched). Staged item →
    /// caller must use trash/restore/move; this is a no-op for staged to avoid
    /// destroying the only copy.
    func remove(_ item: FileShelfItem) {
        guard let it = items.first(where: { $0.id == item.id }) else { return }
        if it.intakeMode == .keepOriginalReference {
            items.removeAll { $0.id == item.id }; persist()
        }
    }

    /// Remove several reference-mode entries (originals untouched); staged items
    /// are left alone (use trash/restore per item).
    func removeReferences(_ ids: [UUID]) {
        for id in ids { if let it = items.first(where: { $0.id == id }) { remove(it) } }
    }

    /// Move several staged items' files to the Trash (recoverable), then drop them.
    func moveSelectionToTrash(_ ids: [UUID]) {
        for id in ids { if let it = items.first(where: { $0.id == id }) { moveToTrash(it) } }
    }

    /// Resolve URLs for a group of ids in the given order.
    func urls(for ids: [UUID]) -> [URL] {
        ids.compactMap { id in items.first(where: { $0.id == id })?.resolveURL() }
    }

    /// Safe removal of a staged item: move its only copy to the Trash first.
    func moveToTrash(_ item: FileShelfItem) {
        if let url = item.resolveURL() {
            do { try engine.moveToTrash(url) }
            catch { lastError = "Couldn't move to Trash: \(error.localizedDescription)"; return }
        }
        items.removeAll { $0.id == item.id }; persist()
    }

    /// Restore a staged item to its original location (or a supplied destination
    /// when the original folder no longer exists). Reference items are a no-op.
    @discardableResult
    func restore(_ item: FileShelfItem, to destination: URL? = nil) -> Bool {
        guard item.intakeMode == .moveIntoShelf, let staged = item.resolveURL() else { return false }
        let target = destination ?? item.originalLocationURL
        do {
            try engine.moveOut(staged, to: target)
            items.removeAll { $0.id == item.id }; persist()
            return true
        } catch {
            lastError = "Couldn't restore “\(item.name)”: \(error.localizedDescription)"
            return false
        }
    }

    /// Move a staged item to a chosen destination directory. Reference items are
    /// a no-op (the original is dragged directly).
    @discardableResult
    func moveTo(_ item: FileShelfItem, directory: URL) -> Bool {
        guard item.intakeMode == .moveIntoShelf, let staged = item.resolveURL() else { return false }
        let target = directory.appendingPathComponent(item.name)
        do {
            try engine.moveOut(staged, to: target)
            items.removeAll { $0.id == item.id }; persist()
            return true
        } catch {
            lastError = "Couldn't move “\(item.name)”: \(error.localizedDescription)"
            return false
        }
    }

    /// Clear the shelf safely: reference entries are dropped; staged items are
    /// moved to the Trash (recoverable) rather than silently destroyed.
    func clear() {
        for it in items where it.intakeMode == .moveIntoShelf {
            if let url = it.resolveURL() { try? engine.moveToTrash(url) }
        }
        items.removeAll(); persist()
    }

    func dismissMoveExplainer() { needsMoveExplainer = false; moveExplained = true }

    // MARK: Lifecycle

    /// On explicit quit: honour reference-item session retention. Staged items
    /// must survive relaunch, so they are never touched here.
    func handleSessionEnd() {
        if retention == .untilSessionEnds {
            let before = items.count
            items.removeAll { $0.intakeMode == .keepOriginalReference }
            if items.count != before { persist() }
        }
    }

    /// TTL pruning applies to reference items only.
    func pruneExpired() {
        guard let ttl = retention.seconds else { return }
        let cutoff = Date().addingTimeInterval(-ttl)
        let before = items.count
        items.removeAll { $0.intakeMode == .keepOriginalReference && $0.addedAt < cutoff }
        if items.count != before { persist() }
    }

    /// Drop staged entries whose backing file vanished (e.g. removed outside the
    /// app). Reference items are kept even when missing so they can show a
    /// broken-reference state.
    private func reconcile() {
        let before = items.count
        items.removeAll { item in
            guard item.intakeMode == .moveIntoShelf else { return false }
            guard let p = item.stagedPath else { return true }
            return !FileManager.default.fileExists(atPath: p)
        }
        if items.count != before { persist() }
    }

    private func persist() { manifest.save(items) }
}

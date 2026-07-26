import Foundation

/// Pure, deterministic clipboard history logic — no `NSPasteboard`, no timers —
/// so dedup, pinning and the max-item cap can be unit-tested directly.
struct ClipboardHistory: Codable, Equatable {
    private(set) var items: [ClipboardItem] = []
    var maxItems: Int = 100

    /// Insert a freshly captured item at the front.
    /// - Consecutive identical copies are deduped (moved to front, date bumped).
    /// - Pinned items are never evicted by the cap.
    /// - Returns true if the history changed.
    @discardableResult
    mutating func insert(_ item: ClipboardItem) -> Bool {
        // Dedup: if an existing (unpinned or pinned) item has the same content,
        // remove it and reinsert at front to reflect recency.
        if let idx = items.firstIndex(where: { $0.isSameContent(as: item) }) {
            var existing = items.remove(at: idx)
            existing.createdAt = item.createdAt
            items.insert(existing, at: 0)
            enforceLimit()
            return true
        }
        items.insert(item, at: 0)
        enforceLimit()
        return true
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
    }

    mutating func clearUnpinned() {
        items.removeAll { !$0.pinned }
    }

    mutating func clearAll() {
        items.removeAll()
    }

    func search(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.preview.lowercased().contains(q) }
    }

    /// Evict oldest unpinned items beyond the cap. Pinned items don't count
    /// against the cap so they are always retained.
    private mutating func enforceLimit() {
        let unpinnedCount = items.filter { !$0.pinned }.count
        guard unpinnedCount > maxItems else { return }
        var toDrop = unpinnedCount - maxItems
        // Remove from the tail (oldest) among unpinned.
        for idx in stride(from: items.count - 1, through: 0, by: -1) where toDrop > 0 {
            if !items[idx].pinned {
                items.remove(at: idx)
                toDrop -= 1
            }
        }
    }
}

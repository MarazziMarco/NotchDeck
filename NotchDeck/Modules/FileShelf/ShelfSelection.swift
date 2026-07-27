import Foundation

/// Pure, testable File Shelf selection model. Uses stable item identifiers (not
/// grid indices). Temporary UI state — not persisted across launches, but kept
/// internally consistent across mutations.
struct ShelfSelection: Equatable {
    private(set) var selected: Set<UUID> = []
    /// Anchor for shift-range selection.
    private(set) var anchor: UUID?

    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }
    func contains(_ id: UUID) -> Bool { selected.contains(id) }

    /// Plain click: select just this item (clears the rest); becomes the anchor.
    mutating func click(_ id: UUID) {
        selected = [id]; anchor = id
    }

    /// Command-click: toggle this item in/out; it becomes the anchor.
    mutating func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        anchor = id
    }

    /// Shift-click: select the contiguous range from the anchor to `id` in the
    /// visible `order`. With no anchor, behaves like a plain click.
    mutating func range(to id: UUID, order: [UUID]) {
        guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) else {
            click(id); return
        }
        let lo = min(a, b), hi = max(a, b)
        selected = Set(order[lo...hi])
        // anchor stays put for further shift-clicks
    }

    mutating func selectAll(_ order: [UUID]) { selected = Set(order); anchor = order.last }
    mutating func clear() { selected = []; anchor = nil }

    /// Drop invalid identifiers (removed / missing items) without disturbing the
    /// remaining valid selection.
    mutating func prune(validIDs: Set<UUID>) {
        selected.formIntersection(validIDs)
        if let a = anchor, !validIDs.contains(a) { anchor = selected.first }
    }

    /// The set to drag when a drag begins on `id`:
    /// - if `id` is already selected → the whole selection, in visible order;
    /// - otherwise → just `id` (and it becomes the sole selection).
    mutating func dragSet(startingAt id: UUID, order: [UUID]) -> [UUID] {
        if selected.contains(id) {
            return order.filter { selected.contains($0) }   // deterministic grid order
        }
        click(id)
        return [id]
    }

    /// The set a command targets when acting on `id`:
    /// - if `id` is selected → the whole selection;
    /// - otherwise → select only `id`, then target it.
    mutating func commandTargets(for id: UUID, order: [UUID]) -> [UUID] {
        if selected.contains(id) { return order.filter { selected.contains($0) } }
        click(id)
        return [id]
    }
}

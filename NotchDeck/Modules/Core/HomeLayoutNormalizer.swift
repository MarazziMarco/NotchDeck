import Foundation

/// Normalises persisted Home-layout data against the set of currently-eligible
/// built-in Home module ids. Removes Community, workspace and unknown/obsolete
/// identifiers (e.g. a stale `community.system-pulse` placement) and de-duplicates,
/// WITHOUT reordering the valid built-in Home modules or resetting the layout.
///
/// Uses stable string identifiers only — never array indexes as identity.
enum HomeLayoutNormalizer {
    /// Keys of persisted Home layout the normaliser owns.
    static func normalize(_ s: inout AppSettings, eligible: Set<String>) {
        func cleaned(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { eligible.contains($0) && seen.insert($0).inserted }
        }
        if let order = s.editorialOrder {
            let next = cleaned(order)
            if next != order { s.editorialOrder = next }
        }
        let hidden = cleaned(s.editorialHidden)
        if hidden != s.editorialHidden { s.editorialHidden = hidden }
        if let fav = s.homeFavorites {
            let next = cleaned(fav)
            if next != fav { s.homeFavorites = next }
        }
        for key in s.homeSizes.keys where !eligible.contains(key) { s.homeSizes[key] = nil }
        for key in s.editorialWidths.keys where !eligible.contains(key) { s.editorialWidths[key] = nil }
    }

    /// True when any persisted Home key still references an ineligible id — used
    /// to decide whether a migration write is needed.
    static func needsNormalization(_ s: AppSettings, eligible: Set<String>) -> Bool {
        let all = (s.editorialOrder ?? []) + s.editorialHidden + (s.homeFavorites ?? [])
            + Array(s.homeSizes.keys) + Array(s.editorialWidths.keys)
        // Duplicate detection within order/favorites also counts as needing a pass.
        if let o = s.editorialOrder, Set(o).count != o.count { return true }
        return all.contains { !eligible.contains($0) }
    }
}

import Foundation
import UniformTypeIdentifiers

/// One inclusion decision for a Downloads candidate.
enum DownloadClassification: String, Equatable {
    case active
    case completedToday
    case excludedOld
    case excludedHidden
    case excludedDirectory
    case excludedStaleTemporary
    case excludedUnverifiedDate     // only a modification date, not observed today
}

/// Source of the resolved completion date (for diagnostics).
enum DownloadDateSource: String, Equatable {
    case spotlightDownloadedDate
    case spotlightDateAdded
    case resourceAddedToDirectoryDate
    case creationDate
    case modificationFallback
    case observedCompletionDate
    case unavailable
}

/// A lightweight, testable snapshot of a Downloads entry. No FS access here, so
/// classification is deterministic and unit-testable.
struct DownloadCandidate: Equatable {
    var name: String
    // Real download metadata (Spotlight), then resource dates.
    var spotlightDownloadedDate: Date?
    var spotlightDateAdded: Date?
    var addedToDirectoryDate: Date?
    var creationDate: Date?
    var modificationDate: Date?
    /// Set when NotchDeck DIRECTLY observed this file arrive/complete this run.
    var observedCompletionDate: Date?
    var isRegularFile: Bool = true
    var isDirectory: Bool = false
    var isHidden: Bool = false
    var isPackage: Bool = false
    var fileSize: Int64 = 0
    var ext: String = ""
    /// True when the temporary item was seen actively changing this run.
    var activelyChanging: Bool = false
    /// True when first seen AFTER the startup baseline (a real arrival event),
    /// not merely present during initial enumeration.
    var firstObservedThisRun: Bool = false
}

/// Authoritative completion-date resolver. A directly-observed completion wins;
/// otherwise real download metadata (Spotlight) is preferred over resource dates;
/// modification date is a strict last resort.
enum DownloadDateResolver {
    static func resolve(_ c: DownloadCandidate) -> (date: Date?, source: DownloadDateSource) {
        if let d = c.observedCompletionDate { return (d, .observedCompletionDate) }
        if let d = c.spotlightDownloadedDate { return (d, .spotlightDownloadedDate) }
        if let d = c.spotlightDateAdded { return (d, .spotlightDateAdded) }
        if let d = c.addedToDirectoryDate { return (d, .resourceAddedToDirectoryDate) }
        if let d = c.creationDate { return (d, .creationDate) }
        if let d = c.modificationDate { return (d, .modificationFallback) }
        return (nil, .unavailable)
    }
}

/// Pure production filter: in-progress downloads + files that COMPLETED today
/// (verified date). Old files are never shown just for a today modification date.
enum DownloadsFilter {
    static let activeExtensions: Set<String> = ["download", "crdownload", "part", "partial"]
    static let limit = 8
    /// Bump when the classification rules change so persisted display state is invalidated.
    static let schemaVersion = 2

    /// Back-compat shim used by older tests.
    static func completionDate(_ c: DownloadCandidate) -> (date: Date?, source: DownloadDateSource) {
        DownloadDateResolver.resolve(c)
    }

    static func isToday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return date >= start && date < tomorrow
    }

    static func classify(_ c: DownloadCandidate, now: Date, calendar: Calendar) -> DownloadClassification {
        if c.isHidden || c.name.hasPrefix(".") { return .excludedHidden }
        if c.isDirectory && !c.isPackage { return .excludedDirectory }
        if activeExtensions.contains(c.ext) {
            // A temporary file only counts as active with evidence of activity —
            // a stale one present since baseline is excluded.
            return c.activelyChanging ? .active : .excludedStaleTemporary
        }
        let (date, source) = DownloadDateResolver.resolve(c)
        guard let date else { return .excludedUnverifiedDate }
        // Modification date alone qualifies ONLY if we observed the file arrive
        // this run; a historical baseline file never does.
        if source == .modificationFallback && !c.firstObservedThisRun {
            return .excludedUnverifiedDate
        }
        return isToday(date, now: now, calendar: calendar) ? .completedToday : .excludedOld
    }

    struct Resolved: Equatable {
        var candidate: DownloadCandidate
        var classification: DownloadClassification
        var completionDate: Date?
        var dateSource: DownloadDateSource
    }

    static func resolveAll(_ candidates: [DownloadCandidate], now: Date,
                           calendar: Calendar = .autoupdatingCurrent) -> [Resolved] {
        candidates.map {
            let (d, src) = DownloadDateResolver.resolve($0)
            return Resolved(candidate: $0, classification: classify($0, now: now, calendar: calendar),
                            completionDate: d, dateSource: src)
        }
    }

    /// Visible list: active first (newest change first), then completed-today
    /// (newest completion first), limited. Excluded items never appear.
    static func visible(_ candidates: [DownloadCandidate], now: Date,
                        calendar: Calendar = .autoupdatingCurrent) -> [Resolved] {
        let resolved = resolveAll(candidates, now: now, calendar: calendar)
        let active = resolved.filter { $0.classification == .active }
            .sorted { ($0.candidate.modificationDate ?? .distantPast) > ($1.candidate.modificationDate ?? .distantPast) }
        let today = resolved.filter { $0.classification == .completedToday }
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        return Array((active + today).prefix(limit))
    }
}

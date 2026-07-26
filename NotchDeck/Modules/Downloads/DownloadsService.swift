import Foundation
import AppKit
import Combine
import CoreServices

struct DownloadItem: Identifiable, Equatable {
    var id: String
    var name: String
    var isActive: Bool
    var byteSize: Int64
    var modified: Date
    var completionTime: Date?
    var classification: DownloadClassification
}

/// Watches the user's Downloads folder and publishes ONLY in-progress downloads
/// and files completed today (local calendar). Old files are never shown. Uses a
/// real directory observer plus a per-candidate size-change observation to tell a
/// live temporary download from a stale one. Honest limitations, public API only.
@MainActor
final class DownloadsService: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var folderAccessible = true

    private var timer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var midnightTimer: Timer?

    /// Per-path observation records for active-download detection.
    private struct Observation { var lastSize: Int64; var lastChange: Date; var firstSeen: Date }
    private var observations: [String: Observation] = [:]
    /// A temporary item is considered active only if it changed within this window.
    var staleInterval: TimeInterval = 90
    /// Stable paths present at startup — their mere presence is NOT a new download
    /// event. Anything appearing later this run is a real arrival.
    private var baseline: Set<String> = []
    private var didBaseline = false

    var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        startDirectoryObserver()
        scheduleMidnightRefresh()
        // Light periodic tick only used while an active download exists.
        let t = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged),
                                               name: .NSCalendarDayChanged, object: nil)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        midnightTimer?.invalidate(); midnightTimer = nil
        dirSource?.cancel(); dirSource = nil
        if dirFD >= 0 { close(dirFD); dirFD = -1 }
        NotificationCenter.default.removeObserver(self)
    }

    /// Number of currently-visible qualifying items.
    var visibleCount: Int { items.count }
    var activeCount: Int { items.filter(\.isActive).count }
    var todayCount: Int { items.filter { $0.classification == .completedToday }.count }

    private func tick() {
        // Avoid aggressive full scans when nothing is active.
        if activeCount > 0 { refresh() }
    }

    @objc private func dayChanged() { refresh(); scheduleMidnightRefresh() }

    func onBecameActive() { refresh() }

    // MARK: Directory observer

    private func startDirectoryObserver() {
        dirSource?.cancel()
        if dirFD >= 0 { close(dirFD) }
        dirFD = open(folder.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.debouncedRefresh() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 { close(fd); self?.dirFD = -1 }
        }
        src.resume()
        dirSource = src
    }

    private var pendingRefresh: DispatchWorkItem?
    private func debouncedRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let cal = Calendar.autoupdatingCurrent
        guard let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { return }
        let interval = max(1, next.timeIntervalSinceNow)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dayChanged() }
        }
        RunLoop.main.add(t, forMode: .common)
        midnightTimer = t
    }

    // MARK: Refresh + filter

    func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey,
                                      .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey,
                                      .isHiddenKey, .isPackageKey, .fileSizeKey, .nameKey]
        guard let entries = try? fm.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: keys, options: []) else {
            folderAccessible = false; items = []; return
        }
        folderAccessible = true
        let now = Date()

        // Establish the startup baseline once: existing files are NOT new events.
        if !didBaseline {
            baseline = Set(entries.map(\.path))
            didBaseline = true
        }

        var candidates: [DownloadCandidate] = []
        var seenPaths = Set<String>()
        for url in entries {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let ext = url.pathExtension.lowercased()
            let size = Int64(v?.fileSize ?? 0)
            seenPaths.insert(url.path)
            let isBaseline = baseline.contains(url.path)
            let arrivedThisRun = !isBaseline   // appeared after startup enumeration
            let spot = spotlightDates(url)

            // Update observation record for change detection.
            let changing: Bool
            if DownloadsFilter.activeExtensions.contains(ext) {
                let prev = observations[url.path]
                if let prev {
                    if size != prev.lastSize {
                        observations[url.path] = Observation(lastSize: size, lastChange: now, firstSeen: prev.firstSeen)
                    }
                    let last = observations[url.path]?.lastChange ?? prev.lastChange
                    changing = now.timeIntervalSince(last) <= staleInterval
                } else {
                    observations[url.path] = Observation(lastSize: size, lastChange: now, firstSeen: now)
                    changing = true   // freshly observed temporary → assume live
                }
            } else {
                changing = false
            }

            let isRegular = v?.isRegularFile ?? true
            let isTemp = DownloadsFilter.activeExtensions.contains(ext)
            // A regular file we DIRECTLY observed arrive this run has a trustworthy
            // observed completion time (even before Spotlight indexes it).
            let observed: Date? = (arrivedThisRun && isRegular && !isTemp) ? now : nil

            candidates.append(DownloadCandidate(
                name: v?.name ?? url.lastPathComponent,
                spotlightDownloadedDate: spot.downloaded,
                spotlightDateAdded: spot.added,
                addedToDirectoryDate: v?.allValues[.addedToDirectoryDateKey] as? Date,
                creationDate: v?.creationDate,
                modificationDate: v?.contentModificationDate,
                observedCompletionDate: observed,
                isRegularFile: isRegular,
                isDirectory: v?.isDirectory ?? false,
                isHidden: v?.isHidden ?? false,
                isPackage: v?.isPackage ?? false,
                fileSize: size,
                ext: ext,
                activelyChanging: changing,
                firstObservedThisRun: arrivedThisRun))
        }
        // Drop observations whose temp files vanished (download finished / removed).
        observations = observations.filter { seenPaths.contains($0.key) }

        let visible = DownloadsFilter.visible(candidates, now: now)
        items = visible.map { r in
            DownloadItem(
                id: r.candidate.name,
                name: r.candidate.name,
                isActive: r.classification == .active,
                byteSize: r.candidate.fileSize,
                modified: r.candidate.modificationDate ?? r.completionDate ?? now,
                completionTime: r.completionDate,
                classification: r.classification)
        }
    }

    /// Read Spotlight download metadata (never via an `mdls` subprocess).
    private func spotlightDates(_ url: URL) -> (downloaded: Date?, added: Date?) {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return (nil, nil) }
        let dl = MDItemCopyAttribute(item, "kMDItemDownloadedDate" as CFString) as? Date
        let ad = MDItemCopyAttribute(item, "kMDItemDateAdded" as CFString) as? Date
        return (dl, ad)
    }

    func openFolder() { NSWorkspace.shared.open(folder) }
}

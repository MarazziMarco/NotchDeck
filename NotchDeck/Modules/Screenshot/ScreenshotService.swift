import AppKit
import Combine

/// Screenshots + screen recording via the public `screencapture` tool.
/// Shows recent screenshots and can start/stop a recording (tracking elapsed
/// time). No private capture APIs.
@MainActor
final class ScreenshotService: ObservableObject {
    @Published private(set) var recent: [URL] = []
    @Published private(set) var isRecording = false
    @Published private(set) var recordingElapsed: TimeInterval = 0

    private var recordProcess: Process?
    private var recordStart: Date?
    private var tickTimer: Timer?
    private var scanTimer: Timer?

    /// Where macOS saves screenshots (falls back to Desktop).
    var saveLocation: URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let path = defaults?.string(forKey: "location") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func start() {
        guard scanTimer == nil else { return }
        scanRecent()
        let t = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanRecent() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        scanTimer = t
    }
    func stop() { scanTimer?.invalidate(); scanTimer = nil }

    func scanRecent() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: saveLocation,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { recent = []; return }
        let images = entries.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased())
            && $0.lastPathComponent.range(of: "Screen", options: .caseInsensitive) != nil }
        recent = images.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }.prefix(6).map { $0 }
    }

    /// Interactive area screenshot to the save location.
    func captureInteractive() {
        let name = "Screenshot \(Self.stamp()).png"
        let dest = saveLocation.appendingPathComponent(name)
        runScreencapture(["-i", dest.path]) { [weak self] in self?.scanRecent() }
    }

    // MARK: Recording

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        let dest = saveLocation.appendingPathComponent("Screen Recording \(Self.stamp()).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -v records video; -x silent. Records the full screen until terminated.
        process.arguments = ["-v", dest.path]
        do { try process.run() } catch { return }
        recordProcess = process
        recordStart = Date()
        isRecording = true
        recordingElapsed = 0
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.recordStart else { return }
                self.recordingElapsed = Date().timeIntervalSince(s)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func stopRecording() {
        recordProcess?.interrupt()   // SIGINT finalizes the recording file
        recordProcess = nil
        isRecording = false
        tickTimer?.invalidate(); tickTimer = nil
        recordStart = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.scanRecent() }
    }

    var formattedElapsed: String {
        let s = Int(recordingElapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func runScreencapture(_ args: [String], completion: @escaping () -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in DispatchQueue.main.async { completion() } }
        try? process.run()
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }
}

import AppKit
import Combine

/// Now Playing via scriptable players (Music.app, Spotify) using public
/// AppleScript automation.
///
/// LIMITATION: macOS has no *public* API to read the system-wide "now playing"
/// info of an arbitrary app (that requires the private MediaRemote framework).
/// So NowPlaying supports the common scriptable players and shows a graceful
/// unavailable state otherwise. Only players that are already running are
/// queried — we never launch them.
@MainActor
final class NowPlayingService: ObservableObject, LiveActivitySource {
    struct Track: Equatable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var app: String        // "Music" or "Spotify"
    }

    @Published private(set) var track: Track?
    /// True when at least one supported player is running.
    @Published private(set) var providerAvailable = false
    /// Album artwork URL (Spotify exposes one; Music does not via AppleScript).
    @Published private(set) var artworkURL: URL?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.notchdeck.nowplaying")

    private static let players: [(bundleID: String, app: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music"),
    ]

    func start() {
        guard timer == nil else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func runningPlayers() -> [(bundleID: String, app: String)] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.players.filter { running.contains($0.bundleID) }
    }

    func poll() {
        let players = runningPlayers()
        providerAvailable = !players.isEmpty
        guard !players.isEmpty else { track = nil; return }
        queue.async { [weak self] in
            guard let self else { return }
            var found: Track?
            for player in players {
                if let t = Self.query(app: player.app), t.isPlaying {
                    found = t; break
                } else if let t = Self.query(app: player.app), found == nil {
                    found = t
                }
            }
            let art = found.flatMap { Self.artwork(app: $0.app) }
            Task { @MainActor in self.track = found; self.artworkURL = art }
        }
    }

    // MARK: AppleScript

    nonisolated private static func query(app: String) -> Track? {
        let script = """
        tell application "\(app)"
            if it is running then
                set st to (player state as text)
                set t to name of current track
                set a to artist of current track
                return st & "||" & t & "||" & a
            end if
        end tell
        """
        guard let out = runOSA(script) else { return nil }
        let parts = out.components(separatedBy: "||")
        guard parts.count == 3 else { return nil }
        let playing = parts[0].lowercased().contains("playing")
        return Track(title: parts[1], artist: parts[2], isPlaying: playing, app: app)
    }

    /// Control commands — no-ops if unsupported.
    func playPause() {
        if track == nil {
            // Nothing playing yet: try to start Apple Music (launches it if needed).
            queue.async {
                _ = Self.runOSA("tell application \"Music\" to play")
                Task { @MainActor in self.poll() }
            }
            return
        }
        runControl("playpause")
    }
    func next() { runControl("next track") }
    func previous() { runControl("previous track") }

    /// Spotify exposes an artwork URL; Music does not via public AppleScript.
    nonisolated static func artwork(app: String) -> URL? {
        guard app == "Spotify" else { return nil }
        guard let s = runOSA("tell application \"Spotify\" to return artwork url of current track"),
              let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return url
    }

    private func runControl(_ command: String) {
        guard let app = track?.app else { return }
        queue.async { _ = Self.runOSA("tell application \"\(app)\" to \(command)") }
    }

    nonisolated private static func runOSA(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch { return nil }
    }

    // MARK: LiveActivitySource

    nonisolated func currentActivity() -> ResolvedActivity? {
        MainActor.assumeIsolated {
            guard let track, track.isPlaying else { return nil }
            let label = track.title.isEmpty ? track.app : track.title
            return ResolvedActivity(
                id: "nowPlaying",
                priority: .media,
                slot: WingSlot(symbol: "music.note", text: String(label.prefix(18)), tint: .neutral),
                preferredWing: .leading,
                tapTarget: .module("nowPlaying"))
        }
    }
}

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
    /// The media boundary. Injected so tests never touch osascript / Music.app.
    private let provider: NowPlayingProviding

    init(provider: NowPlayingProviding = AppleScriptNowPlayingProvider()) {
        self.provider = provider
    }

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

    func poll() {
        queue.async { [weak self, provider] in
            guard let self else { return }
            let snap = provider.snapshot()
            Task { @MainActor in
                self.track = snap.track
                self.providerAvailable = snap.providerAvailable
                self.artworkURL = snap.artworkURL
            }
        }
    }

    /// Control commands — delegated to the provider (no-ops in the fake).
    func playPause() {
        let app = track?.app
        queue.async { [provider] in provider.playPause(currentApp: app) }
        if track == nil { poll() }
    }
    func next() { let app = track?.app; queue.async { [provider] in provider.next(currentApp: app) } }
    func previous() { let app = track?.app; queue.async { [provider] in provider.previous(currentApp: app) } }

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

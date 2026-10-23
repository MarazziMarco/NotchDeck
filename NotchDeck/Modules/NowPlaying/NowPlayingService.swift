import AppKit
import Combine
import SharedWidgets

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

    private var sharedController: SharedMusicController?
    private var sharingObserver: AnyCancellable?
    private let sharedClient = UUID()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.notchdeck.nowplaying")
    /// The media boundary. Injected so tests never touch osascript / Music.app.
    private let provider: NowPlayingProviding

    init(provider: NowPlayingProviding = AppleScriptNowPlayingProvider(), sharedController: SharedMusicController? = nil) {
        self.provider = provider
        if let shared = sharedController ?? (provider is AppleScriptNowPlayingProvider ? SharedWidgetLibrary.shared.musicController : nil) {
            self.sharedController = shared
            sharingObserver = shared.channel.$value.sink { [weak self] value in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.track = value.preferences.enabled ? value.track.map { Track(title: $0.title, artist: $0.artist, isPlaying: $0.isPlaying, app: $0.app) } : nil
                    self.providerAvailable = value.preferences.enabled && value.providerAvailable
                    self.artworkURL = value.track?.artworkURL.flatMap(URL.init(string:))
                }
            }
        }
    }

    func start() {
        if let shared = sharedController { shared.start(client: sharedClient); return }
        guard timer == nil else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        if let shared = sharedController { shared.stop(client: sharedClient); return }
        timer?.invalidate(); timer = nil
    }

    func poll() {
        if let shared = sharedController { shared.poll(); return }
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
        if let shared = sharedController { try? shared.send(.playPause); return }
        let app = track?.app
        queue.async { [provider] in provider.playPause(currentApp: app) }
        if track == nil { poll() }
    }
    func next() { if let shared = sharedController { try? shared.send(.next); return }; let app = track?.app; queue.async { [provider] in provider.next(currentApp: app) } }
    func previous() { if let shared = sharedController { try? shared.send(.previous); return }; let app = track?.app; queue.async { [provider] in provider.previous(currentApp: app) } }

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

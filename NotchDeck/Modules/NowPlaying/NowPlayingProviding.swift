import AppKit

/// Immutable snapshot of the current media state.
struct NowPlayingSnapshot: Equatable {
    var track: NowPlayingService.Track?
    var providerAvailable: Bool
    var artworkURL: URL?
    static let empty = NowPlayingSnapshot(track: nil, providerAvailable: false, artworkURL: nil)
}

/// The media boundary. Production uses AppleScript automation; tests inject a
/// deterministic fake so constructing `AppEnvironment` never launches osascript,
/// sends Apple Events, activates Music.app / Spotify, or triggers an Automation
/// prompt.
protocol NowPlayingProviding: AnyObject {
    /// Read current state. May run off the main thread; must be side-effect-free
    /// beyond querying already-running players.
    func snapshot() -> NowPlayingSnapshot
    func playPause(currentApp: String?)
    func next(currentApp: String?)
    func previous(currentApp: String?)
}

/// Production provider — AppleScript against already-running scriptable players.
/// Never launches a player except on an explicit user play action.
final class AppleScriptNowPlayingProvider: NowPlayingProviding {
    private static let players: [(bundleID: String, app: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music"),
    ]

    private func runningPlayers() -> [(bundleID: String, app: String)] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.players.filter { running.contains($0.bundleID) }
    }

    func snapshot() -> NowPlayingSnapshot {
        let players = runningPlayers()
        guard !players.isEmpty else { return .empty }
        var found: NowPlayingService.Track?
        for player in players {
            if let t = query(app: player.app), t.isPlaying { found = t; break }
            else if found == nil, let t = query(app: player.app) { found = t }
        }
        let art = found.flatMap { artwork(app: $0.app) }
        return NowPlayingSnapshot(track: found, providerAvailable: true, artworkURL: art)
    }

    func playPause(currentApp: String?) {
        if let app = currentApp { _ = Self.runOSA("tell application \"\(app)\" to playpause") }
        else { _ = Self.runOSA("tell application \"Music\" to play") }   // explicit user action may launch Music
    }
    func next(currentApp: String?) { if let a = currentApp { _ = Self.runOSA("tell application \"\(a)\" to next track") } }
    func previous(currentApp: String?) { if let a = currentApp { _ = Self.runOSA("tell application \"\(a)\" to previous track") } }

    private func query(app: String) -> NowPlayingService.Track? {
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
        guard let out = Self.runOSA(script) else { return nil }
        let parts = out.components(separatedBy: "||")
        guard parts.count == 3 else { return nil }
        return NowPlayingService.Track(title: parts[1], artist: parts[2],
                                       isPlaying: parts[0].lowercased().contains("playing"), app: app)
    }

    private func artwork(app: String) -> URL? {
        guard app == "Spotify",
              let s = Self.runOSA("tell application \"Spotify\" to return artwork url of current track"),
              let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return url
    }

    private static func runOSA(_ script: String) -> String? {
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
}

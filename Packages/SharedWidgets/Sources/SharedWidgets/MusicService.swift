import Foundation
import AppKit
import Combine

public struct MusicPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var player = "auto"
    public var showArtwork = true
    public init() {}
}
public struct MusicTrack: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var app: String
    public var isPlaying: Bool
    public var artworkURL: String?
    public var duration: Double
    public var position: Double
    public var capturedAt: Date
    public init(title: String, artist: String, app: String, isPlaying: Bool, artworkURL: String? = nil,
                duration: Double = 0, position: Double = 0, capturedAt: Date = .now) {
        self.title = title; self.artist = artist; self.app = app; self.isPlaying = isPlaying
        self.artworkURL = artworkURL; self.duration = duration; self.position = position; self.capturedAt = capturedAt
    }
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, (position + (isPlaying ? now.timeIntervalSince(capturedAt) : 0)) / duration))
    }
}
public enum MusicAction: String, Codable, Sendable { case playPause, next, previous }
public struct MusicCommand: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var action: MusicAction
    public var createdAt = Date()
    public init(action: MusicAction) { self.action = action }
}
public struct SharedMusic: Codable, Equatable, Sendable {
    public var preferences = MusicPreferences()
    public var track: MusicTrack?
    public var providerAvailable = false
    public var errorMessage: String?
    public var leaseOwner: UUID?
    public var leaseExpiresAt: Date?
    public var commands: [MusicCommand] = []
    public init() {}
    public mutating func claim(owner: UUID, now: Date) -> [MusicCommand]? {
        guard preferences.enabled else { return nil }
        if let current = leaseOwner, current != owner, let expiry = leaseExpiresAt, expiry > now { return nil }
        leaseOwner = owner; leaseExpiresAt = now.addingTimeInterval(8)
        let pending = commands.filter { now.timeIntervalSince($0.createdAt) < 15 }
        commands = []
        return pending
    }
}

public struct MusicReading: Sendable {
    public var track: MusicTrack?
    public var providerAvailable: Bool
    public init(track: MusicTrack?, providerAvailable: Bool) { self.track = track; self.providerAvailable = providerAvailable }
}
public protocol MusicProviding: Sendable {
    func read(player: String) throws -> MusicReading
    func send(_ action: MusicAction, app: String) throws
}

public struct ScriptableMusicProvider: MusicProviding {
    public init() {}
    public func read(player: String) throws -> MusicReading {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = [("spotify", "com.spotify.client", "Spotify"), ("music", "com.apple.Music", "Music")]
            .filter { running.contains($0.1) && (player == "auto" || player == $0.0) }
        var fallback: MusicTrack?
        for (_, _, app) in candidates {
            let art = app == "Spotify" ? "set picture to artwork url of current track" : "set picture to \"\""
            let script = """
            with timeout of 5 seconds
              tell application "\(app)"
                if it is running then
                  set separator to ASCII character 31
                  set statusText to player state as text
                  if statusText is "stopped" then return ""
                  \(art)
                  return statusText & separator & (name of current track) & separator & (artist of current track) & separator & (duration of current track as text) & separator & (player position as text) & separator & picture
                end if
              end tell
            end timeout
            """
            let output = try run(script)
            let fields = output.components(separatedBy: "\u{1f}")
            guard fields.count == 6 else { continue }
            let duration = Double(fields[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            let track = MusicTrack(title: fields[1], artist: fields[2], app: app,
                                   isPlaying: fields[0].lowercased() == "playing",
                                   artworkURL: fields[5].hasPrefix("https://") ? fields[5] : nil,
                                   duration: app == "Spotify" ? duration / 1000 : duration,
                                   position: Double(fields[4].replacingOccurrences(of: ",", with: ".")) ?? 0)
            if track.isPlaying { return MusicReading(track: track, providerAvailable: true) }
            if fallback == nil { fallback = track }
        }
        return MusicReading(track: fallback, providerAvailable: !candidates.isEmpty)
    }
    public func send(_ action: MusicAction, app: String) throws {
        guard ["Music", "Spotify"].contains(app) else { return }
        let verb: String
        switch action { case .playPause: verb = "playpause"; case .next: verb = "next track"; case .previous: verb = "previous track" }
        _ = try run("with timeout of 5 seconds\ntell application \"\(app)\" to \(verb)\nend timeout")
    }
    private func run(_ script: String) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); process.arguments = ["-e", script]
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run(); process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if error.contains("1743") { throw TimetableImportError("Consenti il controllo di Music o Spotify in Impostazioni di Sistema → Privacy e sicurezza → Automazione.") }
            throw TimetableImportError("Il lettore non risponde. Apri Music o Spotify e riprova.")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}

@MainActor public final class SharedMusicController {
    public let channel: SharedWidgetChannel<SharedMusic>
    private let provider: any MusicProviding
    private let owner = UUID()
    private var clients = Set<UUID>()
    private var timer: Timer?
    private var inFlight = false
    private var lastQuery = Date.distantPast
    public init(channel: SharedWidgetChannel<SharedMusic>, provider: any MusicProviding = ScriptableMusicProvider()) {
        self.channel = channel; self.provider = provider
    }
    public func start(client: UUID) {
        clients.insert(client)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer; poll()
    }
    public func stop(client: UUID) {
        clients.remove(client)
        if clients.isEmpty {
            timer?.invalidate(); timer = nil
            try? channel.update { if $0.leaseOwner == owner { $0.leaseOwner = nil; $0.leaseExpiresAt = nil } }
        }
    }
    public func connect() throws { try channel.update { $0.preferences.enabled = true }; poll() }
    public func send(_ action: MusicAction) throws {
        try channel.update {
            $0.preferences.enabled = true
            $0.commands.append(MusicCommand(action: action))
            $0.commands = Array($0.commands.suffix(20))
        }
        poll()
    }
    public func poll() {
        channel.refresh()
        let now = Date()
        guard !inFlight, channel.value.preferences.enabled,
              now.timeIntervalSince(lastQuery) >= 3 || !channel.value.commands.isEmpty else { return }
        if let other = channel.value.leaseOwner, other != owner, let expiry = channel.value.leaseExpiresAt, expiry > now { return }
        var claimed: [MusicCommand]?
        do { try channel.update { claimed = $0.claim(owner: owner, now: now) } }
        catch { return }
        guard let commands = claimed else { return }
        let preferred = channel.value.preferences.player
        let app = preferred == "spotify" ? "Spotify" : (preferred == "music" ? "Music" : (channel.value.track?.app ?? "Music"))
        let provider = self.provider
        inFlight = true
        Task {
            let result = await Task.detached(priority: .utility) { () -> Result<MusicReading, Error> in
                Result {
                    for command in commands { try provider.send(command.action, app: app) }
                    return try provider.read(player: preferred)
                }
            }.value
            inFlight = false; lastQuery = .now
            try? channel.update {
                guard $0.preferences.enabled, $0.leaseOwner == owner else { return }
                switch result {
                case .success(let reading): $0.track = reading.track; $0.providerAvailable = reading.providerAvailable; $0.errorMessage = nil
                case .failure(let error): $0.errorMessage = error.localizedDescription
                }
            }
        }
    }
    deinit { timer?.invalidate() }
}

import XCTest
import SharedWidgets
@testable import NotchDeck

@MainActor
final class SharedProductivityIntegrationTests: XCTestCase {
    func testNoteTitleSyncKeepsBodyAndDefaultHintIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let notch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let launch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let note = QuickNoteService(fileName: "isolated", sharedChannel: notch.note, fileURL: root.appendingPathComponent("native-note.json"))
        XCTAssertEqual(note.title, "", "The default Nota must be a placeholder")
        note.text = "Il contenuto resta qui"
        note.title = "Nota"
        XCTAssertEqual(note.title, "Nota", "Typing a title beginning with Nota must not clear the edit")
        note.title = "Nota personale"
        XCTAssertEqual(note.title, "Nota personale")
        note.title = "Idee"
        launch.note.refresh()
        XCTAssertEqual(launch.note.value.title, "Idee")
        XCTAssertEqual(launch.note.value.text, "Il contenuto resta qui")
        try launch.note.update { $0.title = "Lista della spesa" }
        notch.note.refresh()
        XCTAssertEqual(note.title, "Lista della spesa")
        XCTAssertEqual(note.text, "Il contenuto resta qui")
        note.title = ""
        launch.note.refresh()
        XCTAssertEqual(launch.note.value.title, "")
        XCTAssertEqual(launch.note.value.text, "Il contenuto resta qui")
    }

    func testNativePomodoroAndLaunchPadControlTheSameSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "shared-focus-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: AppPaths.file(name)) }
        let notch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let launch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let service = PomodoroService(notifications: MockNotificationService(), fileName: name, sharedController: notch.focusController)
        service.start()
        launch.focus.refresh()
        XCTAssertTrue(launch.focus.value.engine.isRunning)
        try launch.focusController.pause()
        notch.focus.refresh()
        XCTAssertFalse(service.engine.isRunning)
        var config = service.engine.config; config.workMinutes = 37
        service.updateConfig(config)
        launch.focus.refresh()
        XCTAssertEqual(launch.focus.value.engine.config.workMinutes, 37)
        try launch.focus.update { $0.engine.config.shortBreakMinutes = 7 }
        notch.focus.refresh()
        XCTAssertEqual(service.engine.config.shortBreakMinutes, 7)
        service.resume()
        service.resetActiveStateForQuit()
        launch.focus.refresh()
        XCTAssertTrue(launch.focus.value.engine.isRunning, "Quitting the notch must not stop LaunchPad's shared session")
        try launch.focusController.reset()
    }

    func testNativeShelfAndLaunchPadShareAdditionsAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let notch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let launch = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let engine = FileShelfStaging(root: root.appendingPathComponent("FileShelf"))
        let shelf = FileShelfStore(engine: engine, sharedChannel: notch.shelf)
        shelf.intakeMode = .keepOriginalReference
        let first = root.appendingPathComponent("notch.txt"), second = root.appendingPathComponent("launch.txt")
        try Data("From notch".utf8).write(to: first)
        try Data("From LaunchPad".utf8).write(to: second)
        XCTAssertEqual(shelf.add(urls: [first]), 1)
        launch.shelf.refresh()
        XCTAssertEqual(launch.shelf.value.items.count, 1)
        try launch.shelf.update { $0.preferences.intakeMode = .reference }
        await launch.shelfController.add([second])
        notch.shelf.refresh()
        XCTAssertEqual(shelf.items.count, 2)
        let native = try XCTUnwrap(shelf.items.first { $0.name == "notch.txt" })
        shelf.remove(native)
        launch.shelf.refresh()
        XCTAssertEqual(launch.shelf.value.items.map(\.name), ["launch.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        let id = try XCTUnwrap(launch.shelf.value.items.first?.id)
        try launch.shelfController.remove(id)
        notch.shelf.refresh()
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testNativeMusicReceivesMetadataAndQueuesExactlyOneCommand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SharedWidgetLibrary(directory: root, migrateLegacy: false)
        let provider = SharedMusicIntegrationProvider()
        let shared = SharedMusicController(channel: library.music, provider: provider)
        let native = NowPlayingService(sharedController: shared)
        native.start()
        defer { native.stop() }
        XCTAssertNil(native.track)
        try shared.connect()
        for _ in 0..<100 where native.track == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(native.track?.title, "A shared track")
        XCTAssertNotNil(native.currentActivity())
        native.next()
        for _ in 0..<100 where provider.commandCount == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(provider.commandCount, 1)
    }
}
private final class SharedMusicIntegrationProvider: MusicProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var commandCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func read(player: String) throws -> MusicReading {
        MusicReading(track: MusicTrack(title: "A shared track", artist: "Test", app: "Music", isPlaying: true), providerAvailable: true)
    }
    func send(_ action: MusicAction, app: String) throws { lock.lock(); count += 1; lock.unlock() }
}

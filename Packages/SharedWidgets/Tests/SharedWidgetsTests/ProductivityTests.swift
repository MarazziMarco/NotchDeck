import XCTest
@testable import SharedWidgets

final class ProductivityTests: XCTestCase {
    private var directory: URL!
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent("Widgets-" + UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testFocusPauseResumeAndAbsoluteTime() {
        let start = Date(timeIntervalSince1970: 1000)
        var engine = FocusEngine(); engine.config.workMinutes = 1
        engine.start(now: start)
        XCTAssertEqual(engine.remaining(at: start.addingTimeInterval(15)), 45)
        engine.pause(now: start.addingTimeInterval(15))
        XCTAssertEqual(engine.remaining(at: start.addingTimeInterval(500)), 45)
        engine.resume(now: start.addingTimeInterval(500))
        XCTAssertEqual(engine.remaining(at: start.addingTimeInterval(520)), 25)
    }
    @MainActor func testTwoAppsAdvanceOneFocusSessionOnlyOnce() throws {
        let first = SharedWidgetChannel(key: "focus", initial: SharedFocus(), directory: directory, observe: false)
        let second = SharedWidgetChannel(key: "focus", initial: SharedFocus(), directory: directory, observe: false)
        let a = SharedFocusController(channel: first, ticking: false)
        let b = SharedFocusController(channel: second, ticking: false)
        let start = Date(timeIntervalSince1970: 1000)
        try first.update { $0.engine.config.workMinutes = 1 }
        try a.start(now: start)
        XCTAssertEqual(a.tick(now: start.addingTimeInterval(60)), .work)
        XCTAssertNil(b.tick(now: start.addingTimeInterval(60)))
        XCTAssertEqual(second.value.engine.completedWorkSessions, 1)
        XCTAssertEqual(second.value.engine.phase, .shortBreak)
        try b.pause(now: start.addingTimeInterval(90))
        first.refresh()
        XCTAssertFalse(first.value.engine.isRunning)
        XCTAssertEqual(first.value.engine.remaining(at: start.addingTimeInterval(900)), 270)
    }
    @MainActor func testFocusCanWaitForExplicitNextPhase() throws {
        let channel = SharedWidgetChannel(key: "focus", initial: SharedFocus(), directory: directory, observe: false)
        let controller = SharedFocusController(channel: channel, ticking: false)
        let now = Date(timeIntervalSince1970: 1000)
        try channel.update { $0.preferences.autoAdvance = false; $0.engine.config.workMinutes = 1 }
        try controller.start(now: now)
        controller.tick(now: now.addingTimeInterval(65))
        XCTAssertEqual(channel.value.engine.phase, .shortBreak)
        XCTAssertFalse(channel.value.engine.isRunning)
        try controller.resume(now: now.addingTimeInterval(100))
        XCTAssertTrue(channel.value.engine.isRunning)
    }
    @MainActor func testShelfLinksAndCopiesKeepOriginalsAndSurviveReopening() async throws {
        let first = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        let original = directory.appendingPathComponent("source.txt")
        try Data("Originale intatto".utf8).write(to: original)
        try first.shelf.update { $0.preferences.intakeMode = .reference }
        await first.shelfController.add([original])
        XCTAssertEqual(first.shelf.value.items.count, 1)
        let reference = try XCTUnwrap(first.shelf.value.items.first)
        XCTAssertTrue(reference.isReference)
        try first.shelfController.remove(reference.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        try first.shelf.update { $0.preferences.intakeMode = .copy }
        await first.shelfController.add([original])
        let copy = try XCTUnwrap(first.shelf.value.items.first)
        let stored = try XCTUnwrap(copy.resolveURL())
        XCTAssertNotEqual(stored, original)
        XCTAssertEqual(try Data(contentsOf: stored), try Data(contentsOf: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let reopened = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        XCTAssertEqual(reopened.shelf.value.items.first?.resolveURL(), stored)
    }
    func testShelfDeltaKeepsPeerAdditionsAndDoesNotResurrectPeerRemovals() {
        let a = SharedShelfItem(reference: URL(fileURLWithPath: "/tmp/a"))
        let b = SharedShelfItem(reference: URL(fileURLWithPath: "/tmp/b"))
        let c = SharedShelfItem(reference: URL(fileURLWithPath: "/tmp/c"))
        var state = SharedShelf(); state.items = [b]
        state.merge(local: [a,c], baseline: [a])
        XCTAssertEqual(Set(state.items.map(\.id)), Set([b.id,c.id]))
        state.merge(local: [], baseline: [b])
        XCTAssertEqual(state.items.map(\.id), [c.id])
    }
    func testCountdownNeverGoesNegativeAndIncludesHoursMinutesSeconds() {
        let now = Date(timeIntervalSince1970: 1000)
        var countdown = SharedCountdown(); countdown.target = now.addingTimeInterval(86400 + 7200 + 180 + 4)
        let left = countdown.remaining(at: now)
        XCTAssertEqual(left.days, 1); XCTAssertEqual(left.hours, 2); XCTAssertEqual(left.minutes, 3); XCTAssertEqual(left.seconds, 4)
        XCTAssertEqual(countdown.remaining(at: now.addingTimeInterval(1000000)).days, 0)
        XCTAssertEqual(countdown.remaining(at: now.addingTimeInterval(1000000)).seconds, 0)
    }
    func testHabitsRespectLocalDayAndSettingsPreserveConcurrentCheckIns() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 20))!
        let definition = HabitDefinition(title: "Leggere", target: 2, weekdays: [1,2,3,4,5])
        var state = SharedHabits(); state.configure([definition], title: "Routine", showCompleted: true)
        state.toggle(definition.id, on: monday, calendar: calendar)
        state.toggle(definition.id, on: monday, calendar: calendar)
        XCTAssertEqual(state.habits[0].count(on: monday, calendar: calendar), 2)
        XCTAssertEqual(state.habits[0].streak(at: monday, calendar: calendar), 1)
        var edited = definition; edited.title = "Leggere un libro"
        state.configure([edited], title: "Nuovo titolo", showCompleted: false)
        XCTAssertEqual(state.habits[0].count(on: monday, calendar: calendar), 2)
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        XCTAssertEqual(state.habits[0].count(on: tuesday, calendar: calendar), 0)
        let sunday = calendar.date(byAdding: .day, value: -1, to: monday)!
        state.toggle(definition.id, on: sunday, calendar: calendar)
        XCTAssertEqual(state.habits[0].count(on: sunday, calendar: calendar), 0)
    }
    @MainActor func testShelfRecoversCommittedCopiesWithoutScanningOriginals() throws {
        let root = directory.appendingPathComponent("FileShelf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let committed = root.appendingPathComponent(UUID().uuidString + "--document.txt")
        try Data("Saved copy".utf8).write(to: committed)
        try Data("Partial copy".utf8).write(to: root.appendingPathComponent(".incoming-partial"))
        try Data("[]".utf8).write(to: root.appendingPathComponent("manifest.json"))
        let library = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        _ = library.shelfController
        XCTAssertEqual(library.shelf.value.items.count, 1)
        XCTAssertEqual(library.shelf.value.items.first?.name, "document.txt")
        XCTAssertEqual(library.shelf.value.items.first?.resolveURL()?.resolvingSymlinksInPath(), committed.resolvingSymlinksInPath())
        XCTAssertEqual(library.shelf.value.items.first?.recovered, true)
        library.shelfController.recoverStoredFiles()
        XCTAssertEqual(library.shelf.value.items.count, 1)
    }
    @MainActor func testShelfMovesByDefaultAndRecoversAfterReopening() async throws {
        let first = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        let source = directory.appendingPathComponent("to-move.txt")
        try Data("Keep this data".utf8).write(to: source)
        await first.shelfController.add([source])
        XCTAssertNil(first.shelfController.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let item = try XCTUnwrap(first.shelf.value.items.first)
        XCTAssertEqual(item.originalPath, source.path)
        let stored = try XCTUnwrap(item.resolveURL())
        XCTAssertEqual(try String(contentsOf: stored, encoding: .utf8), "Keep this data")
        let reopened = SharedWidgetLibrary(directory: directory, migrateLegacy: false)
        XCTAssertEqual(reopened.shelf.value.items.first?.id, item.id)
        XCTAssertNotNil(reopened.shelf.value.items.first?.resolveURL())
    }

    func testMusicCommandsHaveOneOwnerAndAreNotReplayedAfterFailover() {
        let first = UUID(), second = UUID(), now = Date()
        var state = SharedMusic(); state.preferences.enabled = true
        state.commands = [MusicCommand(action: .playPause)]
        XCTAssertEqual(state.claim(owner: first, now: now)?.count, 1)
        XCTAssertNil(state.claim(owner: second, now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.claim(owner: second, now: now.addingTimeInterval(10))?.count, 0)
        state.preferences.enabled = false
        XCTAssertNil(state.claim(owner: first, now: now.addingTimeInterval(30)))
    }
    @MainActor func testMusicDoesNotQueryOrLaunchAnythingUntilConnected() async throws {
        let channel = SharedWidgetChannel(key: "music", initial: SharedMusic(), directory: directory, observe: false)
        let fake = FakeMusicProvider()
        let controller = SharedMusicController(channel: channel, provider: fake)
        let client = UUID(); controller.start(client: client)
        controller.poll()
        XCTAssertEqual(fake.reads, 0)
        try controller.connect()
        for _ in 0..<100 where channel.value.track == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(channel.value.track?.title, "Brano di prova")
        XCTAssertEqual(fake.reads, 1)
        try controller.send(.next)
        for _ in 0..<100 where fake.commands == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(fake.commands, 1)
        controller.stop(client: client)
    }
}
private final class FakeMusicProvider: MusicProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var readCount = 0, commandCount = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
    var commands: Int { lock.lock(); defer { lock.unlock() }; return commandCount }
    func read(player: String) throws -> MusicReading {
        lock.lock(); readCount += 1; lock.unlock()
        return MusicReading(track: MusicTrack(title: "Brano di prova", artist: "Artista", app: "Music", isPlaying: true), providerAvailable: true)
    }
    func send(_ action: MusicAction, app: String) throws { lock.lock(); commandCount += 1; lock.unlock() }
}

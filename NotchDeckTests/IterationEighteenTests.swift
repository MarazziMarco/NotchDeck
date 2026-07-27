import XCTest
@testable import NotchDeck

// MARK: Timeout hierarchy

final class TimeoutHierarchyTests: XCTestCase {
    func testInvariantHolds() {
        XCTAssertTrue(HookTimeouts.isValidHierarchy)
        XCTAssertLessThan(HookTimeouts.uiFallbackSeconds, HookTimeouts.helperHardDeadlineSeconds)
        XCTAssertLessThan(HookTimeouts.helperHardDeadlineSeconds, TimeInterval(HookTimeouts.claudeHookTimeoutSeconds))
    }
    func testInstalledHookTimeoutMatches() {
        let merged = HookInstaller.mergeHooks(base: [:], provider: .claudeCode, helper: "/tmp/h")
        let pr = ((merged["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first
        let inner = (pr?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(inner?["timeout"] as? Int, HookTimeouts.claudeHookTimeoutSeconds)
        XCTAssertGreaterThan(HookTimeouts.claudeHookTimeoutSeconds, Int(HookTimeouts.helperHardDeadlineSeconds))
    }
    func testReleaseDecodesFallbackFlag() throws {
        let d = TerminalAgentDecision(requestID: "R", behavior: .deny, fallback: true)
        let data = TerminalAgentCodec.encodeLine(d)!
        let line = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .newlines)
        let back = TerminalAgentCodec.decodeDecision(line)
        XCTAssertEqual(back?.fallback, true)
    }
}

// MARK: Compact approval semantic label

final class CompactApprovalLabelTests: XCTestCase {
    func testWideUsesApprovalWord() {
        XCTAssertEqual(CompactApprovalLabel.text(vendor: .claudeCode, remainingSeconds: 7, availableWidth: 140),
                       "Claude approval")
    }
    func testMediumUsesCountdown() {
        XCTAssertEqual(CompactApprovalLabel.text(vendor: .claudeCode, remainingSeconds: 7, availableWidth: 90),
                       "Claude · 7s")
    }
    func testNarrowUsesWholeNameNotFragment() {
        let t = CompactApprovalLabel.text(vendor: .claudeCode, remainingSeconds: 7, availableWidth: 50)
        XCTAssertEqual(t, "Claude")
        XCTAssertFalse(t.contains("…"))
        XCTAssertFalse(t.contains("Cod"))   // never "Claude Cod..."
    }
    func testCodexVariant() {
        XCTAssertEqual(CompactApprovalLabel.text(vendor: .codex, remainingSeconds: nil, availableWidth: 90), "Codex")
    }
}

// MARK: Home preset geometry + sizes

final class HomePresetGeometryTests: XCTestCase {
    func testPresetsProduceDistinctTokens() {
        let c = HomeLayoutPreset.compact.tokens
        let b = HomeLayoutPreset.balanced.tokens
        let s = HomeLayoutPreset.spacious.tokens
        XCTAssertNotEqual(c, b); XCTAssertNotEqual(b, s); XCTAssertNotEqual(c, s)
        XCTAssertLessThan(c.leadingInset, b.leadingInset)
        XCTAssertLessThan(b.leadingInset, s.leadingInset)
        XCTAssertLessThan(c.moduleGap, s.moduleGap)
        XCTAssertLessThan(c.bottomBreathing, s.bottomBreathing)
        XCTAssertLessThan(c.heightDelta, s.heightDelta)
    }
    func testSizeWidthWeightsDistinct() {
        XCTAssertEqual(EditorialZoneWidth.narrow.multiplier, 0.75, accuracy: 0.001)
        XCTAssertEqual(EditorialZoneWidth.standard.multiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(EditorialZoneWidth.prominent.multiplier, 1.35, accuracy: 0.001)
        XCTAssertLessThan(EditorialZoneWidth.narrow.multiplier, EditorialZoneWidth.prominent.multiplier)
    }
    func testSizeAffectsRatioAllocation() {
        // A prominent module gets a larger ratio than the same module at standard.
        let base = EditorialHomeLayout.ratios(for: .spacious)["quickNote"]!
        XCTAssertGreaterThan(base * EditorialZoneWidth.prominent.multiplier,
                             base * EditorialZoneWidth.narrow.multiplier)
    }
    func testEditorialSizesMapToRealDashboardSizes() {
        XCTAssertEqual(EditorialZoneWidth(.small), .narrow)
        XCTAssertEqual(EditorialZoneWidth(.medium), .standard)
        XCTAssertEqual(EditorialZoneWidth(.large), .prominent)
        XCTAssertEqual(EditorialZoneWidth.narrow.dashboardSize, .small)
        XCTAssertEqual(EditorialZoneWidth.standard.dashboardSize, .medium)
        XCTAssertEqual(EditorialZoneWidth.prominent.dashboardSize, .large)
    }
}

// MARK: Downloads production filter

final class DownloadsFilterTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)   // fixed "today"
    private func today(_ h: Int = 3) -> Date {
        cal.date(byAdding: .hour, value: h, to: cal.startOfDay(for: now))!
    }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: now)! }
    private func file(_ name: String, added: Date? = nil, created: Date? = nil, modified: Date? = nil,
                      dir: Bool = false, hidden: Bool = false, ext: String = "dmg",
                      changing: Bool = false) -> DownloadCandidate {
        DownloadCandidate(name: name, addedToDirectoryDate: added, creationDate: created,
                          modificationDate: modified, isRegularFile: !dir, isDirectory: dir,
                          isHidden: hidden, fileSize: 100, ext: ext, activelyChanging: changing)
    }

    func testCompletedTodayVisible() {
        let c = file("New.dmg", added: today())
        XCTAssertEqual(DownloadsFilter.classify(c, now: now, calendar: cal), .completedToday)
    }
    func testCompletedYesterdayHidden() {
        let c = file("Discord.dmg", added: yesterday)
        XCTAssertEqual(DownloadsFilter.classify(c, now: now, calendar: cal), .excludedOld)
    }
    func testOldFileModifiedTodayStillHidden() {
        // Old added date, but modified today → must NOT be today (added date wins).
        let c = file("ChatGPT-2.dmg", added: yesterday, modified: today())
        XCTAssertEqual(DownloadsFilter.classify(c, now: now, calendar: cal), .excludedOld)
    }
    func testCreationDateUsedWhenAddedMissing() {
        let c = file("x.dmg", added: nil, created: today())
        XCTAssertEqual(DownloadsFilter.completionDate(c).source, .creationDate)
        XCTAssertEqual(DownloadsFilter.classify(c, now: now, calendar: cal), .completedToday)
    }
    func testModificationFallbackOnly() {
        let c = file("x.dmg", added: nil, created: nil, modified: today())
        XCTAssertEqual(DownloadsFilter.completionDate(c).source, .modificationFallback)
    }
    func testHiddenExcluded() {
        XCTAssertEqual(DownloadsFilter.classify(file(".DS_Store", added: today(), hidden: true), now: now, calendar: cal), .excludedHidden)
    }
    func testDirectoryExcluded() {
        XCTAssertEqual(DownloadsFilter.classify(file("Folder", added: today(), dir: true), now: now, calendar: cal), .excludedDirectory)
    }
    func testActiveTempVisible() {
        for e in ["download", "crdownload", "part"] {
            XCTAssertEqual(DownloadsFilter.classify(file("f.\(e)", ext: e, changing: true), now: now, calendar: cal), .active)
        }
    }
    func testStaleTempExcluded() {
        XCTAssertEqual(DownloadsFilter.classify(file("f.part", ext: "part", changing: false), now: now, calendar: cal), .excludedStaleTemporary)
    }
    func testSortActiveBeforeCompleted() {
        let items = [file("done.dmg", added: today(2)), file("live.part", ext: "part", changing: true)]
        let v = DownloadsFilter.visible(items, now: now, calendar: cal)
        XCTAssertEqual(v.first?.classification, .active)
    }
    func testCompletedNewestFirst() {
        let older = file("a.dmg", added: today(1))
        let newer = file("b.dmg", added: today(5))
        let v = DownloadsFilter.visible([older, newer], now: now, calendar: cal)
        XCTAssertEqual(v.first?.candidate.name, "b.dmg")
    }
    func testLimitRespected() {
        let many = (0..<20).map { file("f\($0).dmg", added: today($0 % 12)) }
        XCTAssertLessThanOrEqual(DownloadsFilter.visible(many, now: now, calendar: cal).count, DownloadsFilter.limit)
    }
    func testOldDMGFixturesExcludedFromVisible() {
        let items = [file("Discord.dmg", added: yesterday),
                     file("ChatGPT-2.dmg", added: cal.date(byAdding: .day, value: -7, to: now)),
                     file("Today.dmg", added: today())]
        let names = DownloadsFilter.visible(items, now: now, calendar: cal).map(\.candidate.name)
        XCTAssertEqual(names, ["Today.dmg"])
    }
    func testDayRolloverHidesYesterday() {
        let c = file("y.dmg", added: today())
        XCTAssertEqual(DownloadsFilter.classify(c, now: now, calendar: cal), .completedToday)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DownloadsFilter.classify(c, now: tomorrow, calendar: cal), .excludedOld)
    }
}

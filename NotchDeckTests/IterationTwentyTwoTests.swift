import XCTest
@testable import NotchDeck

/// Downloads metadata-first classification (Spotlight downloaded date, strict
/// modification fallback, baseline vs observed arrival).
final class DownloadsMetadataTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func today(_ h: Int = 3) -> Date { cal.date(byAdding: .hour, value: h, to: cal.startOfDay(for: now))! }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: now)! }
    private var lastWeek: Date { cal.date(byAdding: .day, value: -7, to: now)! }

    private func c(_ name: String, dl: Date? = nil, added: Date? = nil, adt: Date? = nil,
                   created: Date? = nil, modified: Date? = nil, observed: Date? = nil,
                   ext: String = "dmg", changing: Bool = false, arrived: Bool = false) -> DownloadCandidate {
        DownloadCandidate(name: name, spotlightDownloadedDate: dl, spotlightDateAdded: added,
                          addedToDirectoryDate: adt, creationDate: created, modificationDate: modified,
                          observedCompletionDate: observed, ext: ext, activelyChanging: changing,
                          firstObservedThisRun: arrived)
    }
    private func cl(_ x: DownloadCandidate) -> DownloadClassification {
        DownloadsFilter.classify(x, now: now, calendar: cal)
    }

    func testSpotlightDownloadedTodayIncluded() {
        XCTAssertEqual(cl(c("New.dmg", dl: today())), .completedToday)
    }
    func testSpotlightDownloadedYesterdayExcluded() {
        XCTAssertEqual(cl(c("Discord.dmg", dl: yesterday)), .excludedOld)
    }
    func testSpotlightDownloadedBeatsNewerModification() {
        // Downloaded last week but modified today → still OLD (metadata wins).
        XCTAssertEqual(cl(c("ChatGPT-2.dmg", dl: lastWeek, modified: today())), .excludedOld)
        XCTAssertEqual(DownloadDateResolver.resolve(c("x", dl: lastWeek, modified: today())).source, .spotlightDownloadedDate)
    }
    func testSpotlightDateAddedFallback() {
        let r = DownloadDateResolver.resolve(c("x", added: today()))
        XCTAssertEqual(r.source, .spotlightDateAdded)
        XCTAssertEqual(cl(c("x", added: today())), .completedToday)
    }
    func testResourceAddedLowerPriorityThanSpotlight() {
        // Spotlight downloaded (old) present alongside a today resource-added date.
        let r = DownloadDateResolver.resolve(c("x", dl: yesterday, adt: today()))
        XCTAssertEqual(r.source, .spotlightDownloadedDate)
        XCTAssertEqual(cl(c("x", dl: yesterday, adt: today())), .excludedOld)
    }
    func testModificationOnlyBaselineFileExcluded() {
        // Historical file: only a (today) modification date, not observed → hidden.
        XCTAssertEqual(cl(c("old.dmg", modified: today(), arrived: false)), .excludedUnverifiedDate)
    }
    func testModificationOnlyObservedArrivalIncluded() {
        // Same file but observed arriving this run → allowed.
        XCTAssertEqual(cl(c("new.dmg", observed: today(), arrived: true)), .completedToday)
    }
    func testOldDownloadPlusModifiedTodayStillExcluded() {
        XCTAssertEqual(cl(c("v.mov", dl: lastWeek, modified: today())), .excludedOld)
    }
    func testStaleTemporaryBaselineExcluded() {
        XCTAssertEqual(cl(c("f.part", ext: "part", changing: false)), .excludedStaleTemporary)
    }
    func testChangingTemporaryActive() {
        XCTAssertEqual(cl(c("f.crdownload", ext: "crdownload", changing: true)), .active)
    }
    func testNoDateUnverified() {
        XCTAssertEqual(cl(c("mystery")), .excludedUnverifiedDate)
    }
    func testEmptyFilteredNeverIncludesExcluded() {
        // A folder of only historical files → empty visible list (empty state).
        let items = [c("Discord.dmg", dl: yesterday), c("ChatGPT-2.dmg", dl: lastWeek),
                     c("clip.mov", modified: today(), arrived: false)]
        XCTAssertTrue(DownloadsFilter.visible(items, now: now, calendar: cal).isEmpty)
    }
    func testRealFolderMixOnlyTodayShown() {
        let items = [c("Discord.dmg", dl: yesterday),
                     c("ChatGPT-2.dmg", dl: lastWeek),
                     c("Today.pkg", dl: today())]
        let names = DownloadsFilter.visible(items, now: now, calendar: cal).map(\.candidate.name)
        XCTAssertEqual(names, ["Today.pkg"])
    }
    func testSchemaVersionBumped() {
        XCTAssertGreaterThanOrEqual(DownloadsFilter.schemaVersion, 2)
    }
    func testProductionVisibleContainsNoExcluded() {
        let items = [c("a.dmg", dl: today()), c("b.dmg", dl: yesterday),
                     c("c.part", ext: "part"), c("d.mov", modified: today())]
        let vis = DownloadsFilter.visible(items, now: now, calendar: cal)
        for r in vis {
            XCTAssertTrue(r.classification == .active || r.classification == .completedToday)
        }
    }
}

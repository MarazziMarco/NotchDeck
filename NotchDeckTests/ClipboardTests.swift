import XCTest
import AppKit
@testable import NotchDeck

final class ClipboardHistoryTests: XCTestCase {

    private func textItem(_ s: String) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s, stringContent: s)
    }

    func testDeduplicatesConsecutiveIdentical() {
        var h = ClipboardHistory()
        h.insert(textItem("hello"))
        h.insert(textItem("hello"))
        XCTAssertEqual(h.items.count, 1)
    }

    func testDedupMovesToFront() {
        var h = ClipboardHistory()
        h.insert(textItem("a"))
        h.insert(textItem("b"))
        h.insert(textItem("a"))
        XCTAssertEqual(h.items.map(\.preview), ["a", "b"])
    }

    func testEnforcesMaxItems() {
        var h = ClipboardHistory()
        h.maxItems = 3
        for i in 0..<10 { h.insert(textItem("item-\(i)")) }
        XCTAssertEqual(h.items.count, 3)
        XCTAssertEqual(h.items.first?.preview, "item-9")
    }

    func testPinnedItemsSurviveCap() {
        var h = ClipboardHistory()
        h.maxItems = 2
        h.insert(textItem("keep"))
        h.togglePin(id: h.items[0].id)
        for i in 0..<5 { h.insert(textItem("x-\(i)")) }
        XCTAssertTrue(h.items.contains { $0.preview == "keep" })
    }

    func testSerializationRoundTrip() throws {
        var h = ClipboardHistory()
        h.insert(textItem("one"))
        h.insert(textItem("two"))
        let data = try JSONEncoder().encode(h)
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        XCTAssertEqual(decoded.items.map(\.preview), h.items.map(\.preview))
    }

    func testSearchFiltersByPreview() {
        var h = ClipboardHistory()
        h.insert(textItem("apple"))
        h.insert(textItem("banana"))
        XCTAssertEqual(h.search("app").map(\.preview), ["apple"])
    }
}

final class ClipboardPolicyTests: XCTestCase {

    func testTransientTypesAreSkipped() {
        XCTAssertTrue(ClipboardPolicy.shouldSkip(typeNames: ["public.utf8-plain-text",
                                                             "org.nspasteboard.TransientType"]))
        XCTAssertTrue(ClipboardPolicy.shouldSkip(typeNames: ["org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardPolicy.shouldSkip(typeNames: ["public.utf8-plain-text"]))
    }

    func testMakeItemBuildsTextItem() {
        let pb = MockPasteboard()
        pb.typeNames = [NSPasteboard.PasteboardType.string.rawValue]
        pb.strings[.string] = "hello world"
        let item = ClipboardService.makeItem(from: pb, types: pb.typeNames, source: nil)
        XCTAssertEqual(item?.kind, .text)
        XCTAssertEqual(item?.stringContent, "hello world")
    }

    func testMakeItemDetectsURL() {
        let pb = MockPasteboard()
        pb.typeNames = [NSPasteboard.PasteboardType.string.rawValue]
        pb.strings[.string] = "https://example.com"
        let item = ClipboardService.makeItem(from: pb, types: pb.typeNames, source: nil)
        XCTAssertEqual(item?.kind, .url)
    }

    @MainActor
    func testRestoreWritesToPasteboard() {
        let pb = MockPasteboard()
        let writer = MockPasteboardWriter()
        let service = ClipboardService(pasteboard: pb, writer: writer,
                                       store: ClipboardPersistence(url: tempURL()))
        let item = ClipboardItem(kind: .text, preview: "restore me", stringContent: "restore me")
        service.restore(item)
        XCTAssertEqual(writer.restored.count, 1)
        XCTAssertEqual(writer.restored.first?.stringContent, "restore me")
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).json")
    }
}

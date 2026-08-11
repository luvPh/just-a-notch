import XCTest
@testable import JustANotch

final class ClipboardHistoryTests: XCTestCase {
    private func text(_ s: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), createdAt: Date(), pinned: false, kind: .text(s))
    }

    func testRecordInsertsAtFront() {
        var h = ClipboardHistory(unpinnedLimit: 25)
        h.record(text("a"))
        h.record(text("b"))
        XCTAssertEqual(h.items.map { $0.plainText }, ["b", "a"])
    }

    func testDuplicateOfFrontIsIgnored() {
        var h = ClipboardHistory(unpinnedLimit: 25)
        h.record(text("a"))
        h.record(text("a"))
        XCTAssertEqual(h.items.count, 1)
    }

    func testUnpinnedCapEvictsOldest() {
        var h = ClipboardHistory(unpinnedLimit: 3)
        ["a", "b", "c", "d"].forEach { h.record(text($0)) }
        XCTAssertEqual(h.items.map { $0.plainText }, ["d", "c", "b"])
    }

    func testPinnedItemsAreExemptFromCap() {
        var h = ClipboardHistory(unpinnedLimit: 2)
        h.record(text("keep"))
        h.togglePin(h.items[0].id)          // "keep" becomes pinned
        ["a", "b", "c"].forEach { h.record(text($0)) }
        XCTAssertTrue(h.items.contains { $0.plainText == "keep" && $0.pinned })
        XCTAssertEqual(h.items.filter { !$0.pinned }.count, 2)
    }

    func testEvictedReturnsRemovedItemsForCleanup() {
        var h = ClipboardHistory(unpinnedLimit: 1)
        let removedA = h.record(text("a"))   // nothing evicted yet
        XCTAssertTrue(removedA.isEmpty)
        let removedB = h.record(text("b"))   // "a" evicted
        XCTAssertEqual(removedB.map { $0.plainText }, ["a"])
    }
}

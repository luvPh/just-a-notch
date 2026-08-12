import XCTest
@testable import JustANotch

final class SequenceStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test.seqstore")!
        d.removePersistentDomain(forName: "test.seqstore")
        return d
    }
    private func seq(_ name: String) -> TimerSequence {
        TimerSequence(id: UUID(), name: name, segments: [], loopStart: nil, loopEnd: nil, loopCount: 1)
    }

    func testSaveCapsAtFive() {
        let store = SequenceStore(defaults: makeDefaults())
        for i in 0..<7 { store.save(seq("s\(i)")) }
        XCTAssertEqual(store.all.count, 5)
    }

    func testSavePersistsAcrossInstances() {
        let d = makeDefaults()
        let a = SequenceStore(defaults: d)
        let s = seq("keep")
        a.save(s)
        let b = SequenceStore(defaults: d)
        XCTAssertEqual(b.all.map(\.name), ["keep"])
    }

    func testUpdateExistingDoesNotDuplicate() {
        let store = SequenceStore(defaults: makeDefaults())
        var s = seq("one")
        store.save(s)
        s.name = "one-edited"
        store.save(s)
        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all.first?.name, "one-edited")
    }

    func testDeleteRemoves() {
        let store = SequenceStore(defaults: makeDefaults())
        let s = seq("gone")
        store.save(s)
        store.delete(s.id)
        XCTAssertTrue(store.all.isEmpty)
    }
}

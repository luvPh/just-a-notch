import XCTest
@testable import JustANotch

final class TimerSequenceTests: XCTestCase {
    private func seg(_ name: String, _ min: Int) -> TimerSegment {
        TimerSegment(id: UUID(), name: name, minutes: min, soundName: "Ping", colorHex: "#7F77DD")
    }

    func testFlattenNoLoopIsSequential() {
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: nil, loopEnd: nil, loopCount: 1)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "c"])
    }

    func testFlattenLoopRegionRepeats() {
        // đoạn 0..1 lặp 2 lần rồi tới đoạn 2 → a,b,a,b,c
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: 0, loopEnd: 1, loopCount: 2)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "a", "b", "c"])
    }

    func testFlattenLoopTrailingAndLeading() {
        // đoạn 1 lặp 3 lần, có đoạn trước và sau → a,b,b,b,c
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: 1, loopEnd: 1, loopCount: 3)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "b", "b", "c"])
    }
}

import XCTest
@testable import JustANotch

final class TimerSequenceRunTests: XCTestCase {
    private func seg(_ name: String, _ min: Int, _ sound: String) -> TimerSegment {
        TimerSegment(id: UUID(), name: name, minutes: min, soundName: sound, colorHex: "#fff")
    }
    private let cfg = PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5,
                                     longBreakMinutes: 15, roundsBeforeLongBreak: 4)

    @MainActor
    func testRunSequenceAdvancesThroughSegmentsAndChimesPerSegment() {
        var now = Date(timeIntervalSince1970: 0)
        var chimed: [String] = []
        let svc = TimerService(config: { self.cfg }, now: { now },
                               autoStartNext: { true }, chime: { chimed.append($0) })
        svc.startSequence([seg("a", 1, "Glass"), seg("b", 1, "Ping")], label: "test")
        XCTAssertEqual(svc.currentSegmentName, "a")
        XCTAssertEqual(svc.remaining, 60, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 61)
        svc.tickForTest()
        XCTAssertEqual(chimed, ["Glass"])            // âm của đoạn a
        XCTAssertEqual(svc.currentSegmentName, "b")  // sang đoạn b

        now = Date(timeIntervalSince1970: 122)
        svc.tickForTest()
        XCTAssertEqual(chimed, ["Glass", "Ping"])    // âm của đoạn b
        XCTAssertTrue(svc.justFinished)              // hết chuỗi
    }

    @MainActor
    func testStopwatchCountsUp() {
        var now = Date(timeIntervalSince1970: 0)
        let svc = TimerService(config: { self.cfg }, now: { now },
                               autoStartNext: { true }, chime: { _ in })
        svc.startStopwatch()
        XCTAssertEqual(svc.elapsed, 0, accuracy: 0.5)
        now = Date(timeIntervalSince1970: 45)
        svc.tickForTest()
        XCTAssertEqual(svc.elapsed, 45, accuracy: 0.5)
    }
}

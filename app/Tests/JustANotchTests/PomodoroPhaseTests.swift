import XCTest
@testable import JustANotch

final class PomodoroPhaseTests: XCTestCase {
    let cfg = PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5,
                             longBreakMinutes: 15, roundsBeforeLongBreak: 4)

    func testWorkGoesToShortBreakWhenRoundsNotReached() {
        let (phase, rounds) = nextPhase(after: .work, completedWorkRounds: 0, cfg: cfg)
        XCTAssertEqual(phase, .shortBreak)
        XCTAssertEqual(rounds, 1)
    }

    func testFourthWorkGoesToLongBreakAndResetsRounds() {
        let (phase, rounds) = nextPhase(after: .work, completedWorkRounds: 3, cfg: cfg)
        XCTAssertEqual(phase, .longBreak)
        XCTAssertEqual(rounds, 0)
    }

    func testShortBreakGoesBackToWork() {
        let (phase, rounds) = nextPhase(after: .shortBreak, completedWorkRounds: 1, cfg: cfg)
        XCTAssertEqual(phase, .work)
        XCTAssertEqual(rounds, 1)
    }

    func testLongBreakGoesBackToWork() {
        let (phase, _) = nextPhase(after: .longBreak, completedWorkRounds: 0, cfg: cfg)
        XCTAssertEqual(phase, .work)
    }

    func testPhaseDurationsFromConfig() {
        XCTAssertEqual(cfg.duration(for: .work), 25 * 60)
        XCTAssertEqual(cfg.duration(for: .shortBreak), 5 * 60)
        XCTAssertEqual(cfg.duration(for: .longBreak), 15 * 60)
    }
}

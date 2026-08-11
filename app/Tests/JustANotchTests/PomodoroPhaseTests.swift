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

    @MainActor
    func testCountdownUsesInjectedClockAndAdvancesPhaseWhenElapsed() {
        var now = Date(timeIntervalSince1970: 0)
        let cfg = PomodoroConfig(workMinutes: 1, shortBreakMinutes: 1,
                                 longBreakMinutes: 1, roundsBeforeLongBreak: 4)
        var chimes = 0
        let svc = TimerService(config: { cfg }, now: { now },
                               autoStartNext: { true }, chime: { chimes += 1 })
        svc.startPomodoro()
        XCTAssertEqual(svc.phase, .work)
        XCTAssertEqual(svc.remaining, 60, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 30)   // 30s later
        svc.tickForTest()
        XCTAssertEqual(svc.remaining, 30, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 61)   // past end
        svc.tickForTest()
        XCTAssertEqual(svc.phase, .shortBreak)  // auto-advanced
        XCTAssertEqual(chimes, 1)
    }

    @MainActor
    func testPauseWaitsForUserWhenAutoStartOff() {
        var now = Date(timeIntervalSince1970: 0)
        let cfg = PomodoroConfig(workMinutes: 1, shortBreakMinutes: 1,
                                 longBreakMinutes: 1, roundsBeforeLongBreak: 4)
        let svc = TimerService(config: { cfg }, now: { now },
                               autoStartNext: { false }, chime: {})
        svc.startPomodoro()
        now = Date(timeIntervalSince1970: 61)
        svc.tickForTest()
        XCTAssertEqual(svc.phase, .shortBreak)
        XCTAssertFalse(svc.isRunning)           // chờ user bấm
    }
}

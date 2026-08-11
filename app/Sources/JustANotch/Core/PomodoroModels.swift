import Foundation

enum TimerPhase: String, Codable { case work, shortBreak, longBreak }
enum TimerMode { case pomodoro, plain }

struct PomodoroConfig: Equatable {
    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var roundsBeforeLongBreak: Int

    func duration(for phase: TimerPhase) -> TimeInterval {
        switch phase {
        case .work:       return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak:  return TimeInterval(longBreakMinutes * 60)
        }
    }
}

/// Luật chuyển pha Pomodoro. Trả về (pha kế tiếp, số vòng làm đã hoàn tất mới).
/// - Sau .work: tăng vòng; nếu đủ roundsBeforeLongBreak → .longBreak + reset vòng,
///   ngược lại → .shortBreak.
/// - Sau break → .work.
func nextPhase(after phase: TimerPhase,
               completedWorkRounds: Int,
               cfg: PomodoroConfig) -> (TimerPhase, Int) {
    switch phase {
    case .work:
        let done = completedWorkRounds + 1
        if done >= cfg.roundsBeforeLongBreak { return (.longBreak, 0) }
        return (.shortBreak, done)
    case .shortBreak, .longBreak:
        return (.work, completedWorkRounds)
    }
}

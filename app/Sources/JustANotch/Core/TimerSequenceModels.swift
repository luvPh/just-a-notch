import Foundation

/// Viên gạch nhỏ nhất của một chuỗi hẹn giờ.
struct TimerSegment: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var minutes: Int          // >0 = đếm ngược; 0 = đếm lên (stopwatch, chỉ trang Đơn)
    var soundName: String     // key tra trong SoundLibrary
    var colorHex: String
}

/// Một chuỗi đoạn nối nhau + một vùng lặp tuỳ chọn.
struct TimerSequence: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var segments: [TimerSegment]   // ≤ 4
    var loopStart: Int?
    var loopEnd: Int?
    var loopCount: Int             // số lần chạy vùng lặp (≥1)
}

/// Trải phẳng chuỗi: các đoạn trước vùng (1 lần) → vùng [start…end] lặp
/// `loopCount` lần → các đoạn sau vùng (1 lần). Không có vùng lặp hợp lệ thì
/// chạy tuần tự đúng 1 lần.
func flatten(_ s: TimerSequence) -> [TimerSegment] {
    guard let start = s.loopStart, let end = s.loopEnd,
          start >= 0, end < s.segments.count, start <= end, s.loopCount > 1 else {
        return s.segments
    }
    var out: [TimerSegment] = []
    out += s.segments[0..<start]
    for _ in 0..<s.loopCount { out += s.segments[start...end] }
    out += s.segments[(end + 1)...]
    return out
}

// MARK: - Pomodoro dưới dạng chuỗi

extension TimerSequence {
    /// Id cố định cho chuỗi Pomodoro dựng sẵn (không lưu trong SequenceStore).
    static let pomodoroID = UUID(uuidString: "00000000-0000-0000-0000-00000000F0C5")!

    /// Pomodoro = (Làm → Nghỉ ngắn) × (vòng − 1) → Làm → Nghỉ dài.
    static func pomodoro(_ cfg: PomodoroConfig, sound: String) -> TimerSequence {
        let rounds = max(1, cfg.roundsBeforeLongBreak)
        var segs: [TimerSegment] = []
        for r in 1...rounds {
            segs.append(TimerSegment(id: UUID(), name: "Làm \(r)", minutes: max(1, cfg.workMinutes),
                                     soundName: sound, colorHex: "#F25C54"))
            let long = r == rounds
            segs.append(TimerSegment(id: UUID(), name: long ? "Nghỉ dài" : "Nghỉ",
                                     minutes: max(1, long ? cfg.longBreakMinutes : cfg.shortBreakMinutes),
                                     soundName: sound, colorHex: long ? "#5AA9FF" : "#4DD185"))
        }
        return TimerSequence(id: pomodoroID, name: "Pomodoro", segments: segs,
                             loopStart: nil, loopEnd: nil, loopCount: 1)
    }
}

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

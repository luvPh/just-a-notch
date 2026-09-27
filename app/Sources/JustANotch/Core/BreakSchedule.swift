import Foundation

/// Lịch nhắc đứng dậy + uống nước — cố định theo giờ làm: 9:00–12:00 và
/// 13:00–18:00, mỗi 30'. Bỏ các mốc trùng đầu/cuối ca (9:00, 12:00, 13:00,
/// 18:00) ⇒ 9:30…11:30, 13:30…17:30. Chỉ thứ 2–6, bỏ ngày lễ nghỉ chính thức.
enum BreakSchedule {
    /// Khung làm việc (giờ bắt đầu, giờ kết thúc).
    static let blocks: [(start: Int, end: Int)] = [(9, 12), (13, 18)]
    static let intervalMinutes = 30
    /// Một mốc còn "hiệu lực" trong chừng này sau giờ hẹn — notch bận thì chờ,
    /// quá hạn thì bỏ lượt đó.
    static let window: TimeInterval = 5 * 60

    /// Các mốc nhắc trong ngày của `date` (rỗng nếu không phải ngày làm việc).
    static func slots(on date: Date, calendar cal: Calendar = .current) -> [Date] {
        guard isWorkday(date, calendar: cal) else { return [] }
        let day = cal.startOfDay(for: date)
        var out: [Date] = []
        for b in blocks {
            var m = b.start * 60 + intervalMinutes
            while m < b.end * 60 {
                if let d = cal.date(byAdding: .minute, value: m, to: day) { out.append(d) }
                m += intervalMinutes
            }
        }
        return out
    }

    static func isWorkday(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        let wd = cal.component(.weekday, from: date)   // 1 = CN, 7 = T7
        guard (2...6).contains(wd) else { return false }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return true }
        let lunar = VietnameseLunar.lunar(fromSolar: y, m, d)
        return !VietnameseHolidays.holidays(solarM: m, solarD: d, lunar: lunar).contains { $0.isPublic }
    }

    /// Mốc đang tới hạn lúc `now` (đã qua giờ hẹn nhưng chưa quá `window`) và
    /// chưa được xử lý (`> lastHandled`). nil nếu không có.
    static func dueSlot(now: Date, lastHandled: Date?, calendar cal: Calendar = .current) -> Date? {
        slots(on: now, calendar: cal).last { slot in
            slot <= now && now.timeIntervalSince(slot) < window && slot > (lastHandled ?? .distantPast)
        }
    }
}

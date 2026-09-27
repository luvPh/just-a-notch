import XCTest
@testable import JustANotch

final class BreakScheduleTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }
    private func hm(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    func testWeekdaySlots() {
        // 2026-09-28 là thứ Hai.
        let s = BreakSchedule.slots(on: date(2026, 9, 28, 8), calendar: cal).map(hm)
        XCTAssertEqual(s, ["09:30", "10:00", "10:30", "11:00", "11:30",
                           "13:30", "14:00", "14:30", "15:00", "15:30",
                           "16:00", "16:30", "17:00", "17:30"])
    }

    func testWeekendHasNoSlots() {
        XCTAssertTrue(BreakSchedule.slots(on: date(2026, 9, 26), calendar: cal).isEmpty)   // T7
        XCTAssertTrue(BreakSchedule.slots(on: date(2026, 9, 27), calendar: cal).isEmpty)   // CN
    }

    func testPublicHolidayHasNoSlots() {
        // 2025-09-02 (Quốc khánh) là thứ Ba.
        XCTAssertTrue(BreakSchedule.slots(on: date(2025, 9, 2), calendar: cal).isEmpty)
        // 2026-10-20 (Phụ nữ VN, không nghỉ) là thứ Ba → vẫn nhắc.
        XCTAssertFalse(BreakSchedule.slots(on: date(2026, 10, 20), calendar: cal).isEmpty)
    }

    func testDueSlotWindow() {
        let at = date(2026, 9, 28, 10, 30)
        XCTAssertEqual(BreakSchedule.dueSlot(now: date(2026, 9, 28, 10, 30, 10), lastHandled: nil, calendar: cal), at)
        XCTAssertEqual(BreakSchedule.dueSlot(now: date(2026, 9, 28, 10, 34, 59), lastHandled: nil, calendar: cal), at)
        // Quá 5' → bỏ.
        XCTAssertNil(BreakSchedule.dueSlot(now: date(2026, 9, 28, 10, 35, 1), lastHandled: nil, calendar: cal))
        // Đã xử lý → không nhắc lại.
        XCTAssertNil(BreakSchedule.dueSlot(now: date(2026, 9, 28, 10, 31), lastHandled: at, calendar: cal))
        // Giờ nghỉ trưa không có mốc.
        XCTAssertNil(BreakSchedule.dueSlot(now: date(2026, 9, 28, 12, 1), lastHandled: nil, calendar: cal))
    }
}

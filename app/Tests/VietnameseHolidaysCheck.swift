import Foundation

private func check(_ cond: Bool, _ message: String,
                  file: StaticString = #filePath, line: UInt = #line) {
    if !cond { fatalError("\(file):\(line): \(message)") }
}

@main
struct VietnameseHolidaysCheck {
    static func main() {
        // Lễ dương cố định.
        check(VietnameseHolidays.solarHoliday(month: 4, day: 30)?.isPublic == true, "30/4 phải là lễ nghỉ")
        check(VietnameseHolidays.solarHoliday(month: 9, day: 2)?.name.contains("Quốc khánh") == true, "2/9 Quốc khánh")
        check(VietnameseHolidays.solarHoliday(month: 6, day: 15) == nil, "15/6 không phải lễ")

        // Lễ âm cố định.
        check(VietnameseHolidays.lunarHoliday(month: 3, day: 10)?.isPublic == true, "10/3 âm Giỗ Tổ (nghỉ)")
        check(VietnameseHolidays.lunarHoliday(month: 8, day: 15)?.name.contains("Trung Thu") == true, "15/8 âm Trung Thu")
        check(VietnameseHolidays.lunarHoliday(month: 1, day: 1)?.isPublic == true, "mùng 1 Tết")

        // Gộp: 2026-08-10 (một ngày thường) không có lễ.
        let l = VietnameseLunar.lunar(fromSolar: 2026, 8, 10)
        check(VietnameseHolidays.holidays(solarM: 8, solarD: 10, lunar: l).isEmpty, "2026-08-10 không có lễ")

        // Gộp: Quốc khánh xuất hiện qua nhánh dương.
        let l2 = VietnameseLunar.lunar(fromSolar: 2026, 9, 2)
        check(VietnameseHolidays.holidays(solarM: 9, solarD: 2, lunar: l2).contains { $0.name.contains("Quốc khánh") }, "2/9 gộp phải có Quốc khánh")

        print("VietnameseHolidaysCheck OK")
    }
}

import Foundation

/// Một ngày lễ. `isPublic` = ngày nghỉ chính thức (đánh dấu đậm); còn lại là
/// lễ/tết truyền thống hoặc lễ phổ biến (đánh dấu mờ).
struct Holiday: Equatable {
    let name: String
    let isPublic: Bool
}

/// Bộ ngày lễ Việt Nam, tra theo ngày dương cố định và ngày âm cố định.
/// Không phân biệt khi hiển thị: một ô lịch tra cả hai nguồn.
enum VietnameseHolidays {
    /// Lễ theo ngày DƯƠNG cố định.
    static func solarHoliday(month: Int, day: Int) -> Holiday? {
        switch (month, day) {
        case (1, 1):   return Holiday(name: "Tết Dương lịch", isPublic: true)
        case (4, 30):  return Holiday(name: "Giải phóng miền Nam", isPublic: true)
        case (5, 1):   return Holiday(name: "Quốc tế Lao động", isPublic: true)
        case (9, 2):   return Holiday(name: "Quốc khánh", isPublic: true)
        case (2, 14):  return Holiday(name: "Valentine", isPublic: false)
        case (3, 8):   return Holiday(name: "Quốc tế Phụ nữ", isPublic: false)
        case (10, 20): return Holiday(name: "Phụ nữ Việt Nam", isPublic: false)
        case (11, 20): return Holiday(name: "Nhà giáo Việt Nam", isPublic: false)
        case (12, 24): return Holiday(name: "Giáng sinh", isPublic: false)
        case (12, 25): return Holiday(name: "Giáng sinh", isPublic: false)
        default:       return nil
        }
    }

    /// Lễ theo ngày ÂM cố định.
    static func lunarHoliday(month: Int, day: Int) -> Holiday? {
        switch (month, day) {
        case (1, 1):   return Holiday(name: "Tết Nguyên Đán", isPublic: true)
        case (1, 2):   return Holiday(name: "Tết Nguyên Đán", isPublic: true)
        case (1, 3):   return Holiday(name: "Tết Nguyên Đán", isPublic: true)
        case (3, 10):  return Holiday(name: "Giỗ Tổ Hùng Vương", isPublic: true)
        case (1, 15):  return Holiday(name: "Rằm tháng Giêng", isPublic: false)
        case (5, 5):   return Holiday(name: "Tết Đoan Ngọ", isPublic: false)
        case (7, 15):  return Holiday(name: "Vu Lan", isPublic: false)
        case (8, 15):  return Holiday(name: "Tết Trung Thu", isPublic: false)
        case (12, 23): return Holiday(name: "Ông Công Ông Táo", isPublic: false)
        default:       return nil
        }
    }

    /// Gộp lễ dương + lễ âm cho một ngày (không phân biệt nguồn).
    /// Truyền ngày dương (month/day) và LunarDate tương ứng của cùng ô.
    static func holidays(solarM: Int, solarD: Int, lunar: LunarDate) -> [Holiday] {
        var out: [Holiday] = []
        if let s = solarHoliday(month: solarM, day: solarD) { out.append(s) }
        // Giao thừa: ngày cuối tháng Chạp (29 hoặc 30) — xử lý động.
        if lunar.month == 12,
           lunar.day == VietnameseLunar.daysInLunarMonth(month: 12, year: lunar.year, isLeap: false) {
            out.append(Holiday(name: "Giao thừa", isPublic: true))
        }
        if let l = lunarHoliday(month: lunar.month, day: lunar.day), !lunar.isLeapMonth {
            out.append(l)
        }
        return out
    }
}

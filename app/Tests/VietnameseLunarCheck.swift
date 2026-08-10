import Foundation

private func check(_ cond: Bool, _ message: String,
                  file: StaticString = #filePath, line: UInt = #line) {
    if !cond { fatalError("\(file):\(line): \(message)") }
}

@main
struct VietnameseLunarCheck {
    static func main() {
        // Mùng 1 Tết các năm mốc (nguồn: lịch VN chuẩn).
        let tet2024 = VietnameseLunar.lunar(fromSolar: 2024, 2, 10)
        check(tet2024.day == 1 && tet2024.month == 1, "2024-02-10 phải là mùng 1/1 âm, got \(tet2024)")

        let tet2025 = VietnameseLunar.lunar(fromSolar: 2025, 1, 29)
        check(tet2025.day == 1 && tet2025.month == 1, "2025-01-29 phải là mùng 1/1 âm, got \(tet2025)")

        let tet2026 = VietnameseLunar.lunar(fromSolar: 2026, 2, 17)
        check(tet2026.day == 1 && tet2026.month == 1, "2026-02-17 phải là mùng 1/1 âm, got \(tet2026)")

        // Ngày trước Tết 2026 phải là tháng Chạp (12) năm trước.
        let eve = VietnameseLunar.lunar(fromSolar: 2026, 2, 16)
        check(eve.month == 12, "2026-02-16 phải thuộc tháng Chạp, got \(eve)")

        // Can Chi năm.
        check(VietnameseLunar.canChi(year: 2024) == "Giáp Thìn", "2024 phải là Giáp Thìn, got \(VietnameseLunar.canChi(year: 2024))")
        check(VietnameseLunar.canChi(year: 2025) == "Ất Tỵ", "2025 phải là Ất Tỵ, got \(VietnameseLunar.canChi(year: 2025))")
        check(VietnameseLunar.canChi(year: 2026) == "Bính Ngọ", "2026 phải là Bính Ngọ, got \(VietnameseLunar.canChi(year: 2026))")

        // Round-trip solar -> lunar -> solar trên vài ngày.
        for (y, m, d) in [(2026, 8, 10), (2024, 2, 10), (2025, 6, 1), (2026, 12, 31)] {
            let l = VietnameseLunar.lunar(fromSolar: y, m, d)
            let s = VietnameseLunar.solar(fromLunar: l.day, l.month, l.year, isLeap: l.isLeapMonth)
            check(s.y == y && s.m == m && s.d == d, "round-trip \(y)-\(m)-\(d) lệch: got \(s) qua \(l)")
        }

        // daysInLunarMonth phải là 29 hoặc 30.
        let len = VietnameseLunar.daysInLunarMonth(month: tet2026.month, year: tet2026.year, isLeap: false)
        check(len == 29 || len == 30, "độ dài tháng âm phải 29/30, got \(len)")

        print("VietnameseLunarCheck OK")
    }
}

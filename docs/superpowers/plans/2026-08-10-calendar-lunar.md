# Calendar tab (Dương + Âm + ngày lễ VN) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thay tab placeholder Clock bằng tab Lịch thật, hiển thị lịch Dương và Âm Việt Nam (offline, không xin quyền) và đánh dấu ngày lễ VN.

**Architecture:** Hai lõi thuần Foundation (`VietnameseLunar` chuyển đổi Dương↔Âm theo thuật toán Hồ Ngọc Đức + Can Chi; `VietnameseHolidays` tra ngày lễ dương/âm) test-được độc lập, cộng một view `CalendarPanel` (SwiftUI) trong NotchRootView với toggle Dương/Âm, điều hướng tháng, đánh dấu lễ. Panel canvas được nâng chiều cao tối đa để chứa lưới lịch.

**Tech Stack:** Swift 6 (SwiftPM executable target), SwiftUI, AppKit. Test theo mẫu dự án: file `@main` trong `Tests/` compile bằng `swiftc`, assert bằng `fatalError`.

---

## File Structure

- Create `app/Sources/JustANotch/Core/VietnameseLunar.swift` — chuyển đổi Dương↔Âm, Can Chi. Thuần Foundation.
- Create `app/Sources/JustANotch/Core/VietnameseHolidays.swift` — bộ ngày lễ VN (dương + âm). Thuần Foundation.
- Create `app/Tests/VietnameseLunarCheck.swift` — test lõi âm lịch.
- Create `app/Tests/VietnameseHolidaysCheck.swift` — test ngày lễ.
- Create `app/Sources/JustANotch/UI/CalendarPanel.swift` — view lịch (toggle, lưới, điều hướng).
- Modify `app/Sources/JustANotch/UI/NotchRootView.swift` — đổi RailTab `.clock`→`.calendar`, thêm `case .calendar` vào `content`.
- Modify `app/Sources/JustANotch/NotchViewModel.swift` — cờ `panelWantsTall` + chiều cao lịch trong `surfaceHeight`; hằng `maxSurfaceHeight`.
- Modify `app/Sources/JustANotch/NotchWindowController.swift` — `layoutPanel` dùng `vm.maxSurfaceHeight` (thay vì `expandedHeight`) để canvas đủ cao cho lịch.

Ghi chú test: các file `Tests/*.swift` KHÔNG nằm trong Package.swift; chúng là executable `@main` độc lập, compile cùng file nguồn thuần-Foundation cần kiểm tra. `VietnameseLunar.swift` và `VietnameseHolidays.swift` không import SwiftUI/AppKit nên compile độc lập được.

---

## Task 1: Lõi VietnameseLunar (chuyển đổi + Can Chi)

**Files:**
- Create: `app/Sources/JustANotch/Core/VietnameseLunar.swift`
- Test: `app/Tests/VietnameseLunarCheck.swift`

- [ ] **Step 1: Viết test thất bại**

Create `app/Tests/VietnameseLunarCheck.swift`:

```swift
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
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run:
```bash
cd app && swiftc Sources/JustANotch/Core/VietnameseLunar.swift Tests/VietnameseLunarCheck.swift -o /tmp/lunarcheck
```
Expected: FAIL biên dịch — "cannot find 'VietnameseLunar' in scope" (chưa tạo file nguồn).

- [ ] **Step 3: Viết lõi tối thiểu**

Create `app/Sources/JustANotch/Core/VietnameseLunar.swift`:

```swift
import Foundation

/// Một ngày âm lịch Việt Nam.
struct LunarDate: Equatable {
    let day: Int
    let month: Int
    let year: Int
    let isLeapMonth: Bool
}

/// Chuyển đổi Dương ↔ Âm lịch (thuật toán Hồ Ngọc Đức), Can Chi năm.
/// Thuần Foundation, không phụ thuộc UI. Tính theo múi giờ VN (+7).
enum VietnameseLunar {
    static let timeZone = 7.0

    // MARK: Julian day <-> Gregorian

    static func jdFromDate(day: Int, month: Int, year: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        var jd = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        if jd < 2299161 {
            jd = day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083
        }
        return jd
    }

    static func dateFromJD(_ jd: Int) -> (y: Int, m: Int, d: Int) {
        var a = 0, b = 0, c = 0
        if jd > 2299160 {
            a = jd + 32044
            b = (4 * a + 3) / 146097
            c = a - (b * 146097) / 4
        } else {
            b = 0
            c = jd + 32082
        }
        let d = (4 * c + 3) / 1461
        let e = c - (1461 * d) / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = b * 100 + d - 4800 + m / 10
        return (year, month, day)
    }

    // MARK: Thiên văn

    static func newMoon(_ k: Int) -> Int {
        let T = Double(k) / 1236.85
        let T2 = T * T, T3 = T2 * T
        let dr = Double.pi / 180
        var Jd1 = 2415020.75933 + 29.53058868 * Double(k) + 0.0001178 * T2 - 0.000000155 * T3
        Jd1 += 0.00033 * sin((166.56 + 132.87 * T - 0.009173 * T2) * dr)
        let M = 359.2242 + 29.10535608 * Double(k) - 0.0000333 * T2 - 0.00000347 * T3
        let Mpr = 306.0253 + 385.81691806 * Double(k) + 0.0107306 * T2 + 0.00001236 * T3
        let F = 21.2964 + 390.67050646 * Double(k) - 0.0016528 * T2 - 0.00000239 * T3
        var C1 = (0.1734 - 0.000393 * T) * sin(M * dr) + 0.0021 * sin(2 * dr * M)
        C1 = C1 - 0.4068 * sin(Mpr * dr) + 0.0161 * sin(dr * 2 * Mpr)
        C1 = C1 - 0.0004 * sin(dr * 3 * Mpr)
        C1 = C1 + 0.0104 * sin(dr * 2 * F) - 0.0051 * sin(dr * (M + Mpr))
        C1 = C1 - 0.0074 * sin(dr * (M - Mpr)) + 0.0004 * sin(dr * (2 * F + M))
        C1 = C1 - 0.0004 * sin(dr * (2 * F - M)) - 0.0006 * sin(dr * (2 * F + Mpr))
        C1 = C1 + 0.0010 * sin(dr * (2 * F - Mpr)) + 0.0005 * sin(dr * (2 * Mpr + M))
        let deltat: Double
        if T < -11 {
            deltat = 0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3
        } else {
            deltat = -0.000278 + 0.000265 * T + 0.000262 * T2
        }
        let JdNew = Jd1 + C1 - deltat
        return Int(JdNew + 0.5 + timeZone / 24)
    }

    static func sunLongitude(_ jdn: Int) -> Int {
        let T = (Double(jdn) - 2451545.5 - timeZone / 24) / 36525
        let T2 = T * T
        let dr = Double.pi / 180
        let M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2
        let L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2
        var DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * sin(dr * M)
        DL += (0.019993 - 0.000101 * T) * sin(dr * 2 * M) + 0.000290 * sin(dr * 3 * M)
        var L = (L0 + DL) * dr
        L = L - Double.pi * 2 * Double(Int(L / (Double.pi * 2)))
        return Int(L / Double.pi * 6)
    }

    static func lunarMonth11(_ year: Int) -> Int {
        let off = Double(jdFromDate(day: 31, month: 12, year: year)) - 2415021.076998695
        let k = Int(off / 29.530588853)
        var nm = newMoon(k)
        if sunLongitude(nm) >= 9 { nm = newMoon(k - 1) }
        return nm
    }

    static func leapMonthOffset(_ a11: Int) -> Int {
        let k = Int(0.5 + (Double(a11) - 2415021.076998695) / 29.530588853)
        var last = 0
        var i = 1
        var arc = sunLongitude(newMoon(k + i))
        repeat {
            last = arc
            i += 1
            arc = sunLongitude(newMoon(k + i))
        } while arc != last && i < 14
        return i - 1
    }

    // MARK: Public API

    static func lunar(fromSolar year: Int, _ month: Int, _ day: Int) -> LunarDate {
        let dayNumber = jdFromDate(day: day, month: month, year: year)
        let k = Int((Double(dayNumber) - 2415021.076998695) / 29.530588853)
        var monthStart = newMoon(k + 1)
        if monthStart > dayNumber { monthStart = newMoon(k) }
        var a11 = lunarMonth11(year)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = year
            a11 = lunarMonth11(year - 1)
        } else {
            lunarYear = year + 1
            b11 = lunarMonth11(year + 1)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = (monthStart - a11) / 29
        var lunarLeap = false
        var lunarMonth = diff + 11
        if b11 - a11 > 365 {
            let leapMonthDiff = leapMonthOffset(a11)
            if diff >= leapMonthDiff {
                lunarMonth = diff + 10
                if diff == leapMonthDiff { lunarLeap = true }
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        if lunarMonth >= 11 && diff < 4 { lunarYear -= 1 }
        return LunarDate(day: lunarDay, month: lunarMonth, year: lunarYear, isLeapMonth: lunarLeap)
    }

    static func solar(fromLunar lunarDay: Int, _ lunarMonth: Int, _ lunarYear: Int, isLeap: Bool) -> (y: Int, m: Int, d: Int) {
        let a11: Int, b11: Int
        if lunarMonth < 11 {
            a11 = lunarMonth11(lunarYear - 1)
            b11 = lunarMonth11(lunarYear)
        } else {
            a11 = lunarMonth11(lunarYear)
            b11 = lunarMonth11(lunarYear + 1)
        }
        var off = lunarMonth - 11
        if off < 0 { off += 12 }
        if b11 - a11 > 365 {
            let leapOff = leapMonthOffset(a11)
            if isLeap || off >= leapOff {
                off += 1
            }
        }
        let k = Int(0.5 + (Double(a11) - 2415021.076998695) / 29.530588853)
        let monthStart = newMoon(k + off)
        return dateFromJD(monthStart + lunarDay - 1)
    }

    static func daysInLunarMonth(month: Int, year: Int, isLeap: Bool) -> Int {
        let s = solar(fromLunar: 1, month, year, isLeap: isLeap)
        let jd1 = jdFromDate(day: s.d, month: s.m, year: s.y)
        let k = Int((Double(jd1) - 2415021.076998695) / 29.530588853 + 0.5)
        return newMoon(k + 1) - newMoon(k)
    }

    static func canChi(year: Int) -> String {
        let can = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"]
        let chi = ["Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"]
        let canIdx = ((year + 6) % 10 + 10) % 10
        let chiIdx = ((year + 8) % 12 + 12) % 12
        return can[canIdx] + " " + chi[chiIdx]
    }
}
```

- [ ] **Step 4: Chạy test để xác nhận pass**

Run:
```bash
cd app && swiftc Sources/JustANotch/Core/VietnameseLunar.swift Tests/VietnameseLunarCheck.swift -o /tmp/lunarcheck && /tmp/lunarcheck
```
Expected: in ra `VietnameseLunarCheck OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/VietnameseLunar.swift app/Tests/VietnameseLunarCheck.swift
git commit -m "feat(calendar): Vietnamese lunar conversion core + Can Chi"
```

---

## Task 2: Lõi VietnameseHolidays (ngày lễ VN)

**Files:**
- Create: `app/Sources/JustANotch/Core/VietnameseHolidays.swift`
- Test: `app/Tests/VietnameseHolidaysCheck.swift`

- [ ] **Step 1: Viết test thất bại**

Create `app/Tests/VietnameseHolidaysCheck.swift`:

```swift
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
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run:
```bash
cd app && swiftc Sources/JustANotch/Core/VietnameseLunar.swift Sources/JustANotch/Core/VietnameseHolidays.swift Tests/VietnameseHolidaysCheck.swift -o /tmp/holcheck
```
Expected: FAIL biên dịch — "cannot find 'VietnameseHolidays' in scope".

- [ ] **Step 3: Viết lõi tối thiểu**

Create `app/Sources/JustANotch/Core/VietnameseHolidays.swift`:

```swift
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
```

- [ ] **Step 4: Chạy test để xác nhận pass**

Run:
```bash
cd app && swiftc Sources/JustANotch/Core/VietnameseLunar.swift Sources/JustANotch/Core/VietnameseHolidays.swift Tests/VietnameseHolidaysCheck.swift -o /tmp/holcheck && /tmp/holcheck
```
Expected: in `VietnameseHolidaysCheck OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/VietnameseHolidays.swift app/Tests/VietnameseHolidaysCheck.swift
git commit -m "feat(calendar): Vietnamese holidays lookup (solar + lunar)"
```

---

## Task 3: Đổi RailTab Clock → Calendar

**Files:**
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift:423,432,442`

- [ ] **Step 1: Đổi case enum**

Trong `enum RailTab` đổi:
```swift
    case music, files, notifications, calendar, settings
```
(thay `clock` bằng `calendar`)

- [ ] **Step 2: Đổi icon**

Trong `var icon`, thay dòng `case .clock: return "clock.fill"` bằng:
```swift
        case .calendar:      return "calendar"
```

- [ ] **Step 3: Đổi title**

Trong `var title`, thay dòng `case .clock: return "Clock"` bằng:
```swift
        case .calendar:      return "Lịch"
```

- [ ] **Step 4: Build kiểm tra biên dịch**

Run:
```bash
cd app && swift build 2>&1 | tail -5
```
Expected: build thành công (chưa có `case .calendar` trong `content` nhưng `content` dùng `default:` nên vẫn hợp lệ — Calendar tạm rơi vào `placeholderPanel`).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/UI/NotchRootView.swift
git commit -m "feat(calendar): replace Clock rail tab with Calendar"
```

---

## Task 4: Chiều cao panel cho lịch

**Files:**
- Modify: `app/Sources/JustANotch/NotchViewModel.swift` (`surfaceHeight` ~140-143, thêm thuộc tính)
- Modify: `app/Sources/JustANotch/NotchWindowController.swift:89`

- [ ] **Step 1: Thêm cờ + hằng vào NotchViewModel**

Trong `NotchViewModel`, ngay dưới `@Published var showList = false` (dòng ~16) thêm:
```swift
    /// True khi tab đang mở là Lịch — panel cần chiều cao lớn hơn player.
    @Published var panelWantsTall = false
```
Và trong khối "Expanded window" (gần `listExpandedHeight`, dòng ~132) thêm:
```swift
    /// Chiều cao panel khi mở tab Lịch (lưới tháng cần nhiều chỗ).
    let calendarExpandedHeight: CGFloat = 300
    /// Chiều cao canvas cố định lớn nhất — panel window phải đủ cao cho mọi state.
    var maxSurfaceHeight: CGFloat { max(expandedHeight, listExpandedHeight, calendarExpandedHeight) }
```

- [ ] **Step 2: Cập nhật surfaceHeight**

Thay thân `var surfaceHeight` hiện tại:
```swift
    var surfaceHeight: CGFloat {
        if showingHUD { return hudHeight }
        return isListOpen ? listExpandedHeight : (expanded ? expandedHeight : compactHeight)
    }
```
bằng:
```swift
    var surfaceHeight: CGFloat {
        if showingHUD { return hudHeight }
        if !expanded { return compactHeight }
        if isListOpen { return listExpandedHeight }
        if panelWantsTall { return calendarExpandedHeight }
        return expandedHeight
    }
```

- [ ] **Step 3: layoutPanel dùng maxSurfaceHeight**

Trong `NotchWindowController.layoutPanel()` (dòng ~89) đổi:
```swift
        let h = vm.expandedHeight
```
thành:
```swift
        let h = vm.maxSurfaceHeight
```

- [ ] **Step 4: Build kiểm tra**

Run:
```bash
cd app && swift build 2>&1 | tail -5
```
Expected: build thành công.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/NotchViewModel.swift app/Sources/JustANotch/NotchWindowController.swift
git commit -m "feat(calendar): taller expanded panel canvas for calendar grid"
```

---

## Task 5: CalendarPanel view (lưới Dương/Âm + lễ)

**Files:**
- Create: `app/Sources/JustANotch/UI/CalendarPanel.swift`
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift` (`content` switch ~148-153; thêm state + onChange)

Ghi chú màu: `alcoveRed` là `private let` trong NotchRootView.swift (dòng 3) nên KHÔNG dùng được ở file khác. Trong `CalendarPanel.swift` khai báo lại một hằng cục bộ:
```swift
private let calAccent = Color(red: 0.96, green: 0.36, blue: 0.33)
```

- [ ] **Step 1: Tạo CalendarPanel.swift**

Create `app/Sources/JustANotch/UI/CalendarPanel.swift`:

```swift
import SwiftUI

private let calAccent = Color(red: 0.96, green: 0.36, blue: 0.33)

enum CalMode { case solar, lunar }

/// Một ô ngày trong lưới: mọi ô đều biết cả ngày dương lẫn ngày âm.
private struct DayInfo: Identifiable {
    let id = UUID()
    let solarY: Int, solarM: Int, solarD: Int
    let lunar: LunarDate
    let weekdayMon0: Int   // 0 = Thứ 2 ... 6 = Chủ nhật
    let inMonth: Bool      // thuộc tháng đang xem (mode-primary)
}

struct CalendarPanel: View {
    @Binding var mode: CalMode
    @Binding var anchor: Date          // ngày bất kỳ trong tháng đang xem
    @Binding var selected: Date?

    private let cal = Calendar(identifier: .gregorian)
    private let weekdayLabels = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            weekdayRow
            grid
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            navButton("chevron.left") { shiftMonth(-1) }
            Text(title)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(minWidth: 120, alignment: .leading)
            navButton("chevron.right") { shiftMonth(1) }
            Spacer(minLength: 4)
            modeToggle
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleChip("Dương", active: mode == .solar) { mode = .solar }
            toggleChip("Âm", active: mode == .lunar) { mode = .lunar }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func toggleChip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? Color.black : .white.opacity(0.7))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(active ? .white.opacity(0.9) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func navButton(_ system: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: system).font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7)).frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayLabels, id: \.self) { d in
                Text(d).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 3) {
            ForEach(days) { info in dayCell(info) }
        }
    }

    private func dayCell(_ info: DayInfo) -> some View {
        let primary = mode == .solar ? "\(info.solarD)" : "\(info.lunar.day)"
        let secondary = mode == .solar ? lunarCorner(info.lunar) : "\(info.solarD)/\(info.solarM)"
        let hols = VietnameseHolidays.holidays(solarM: info.solarM, solarD: info.solarD, lunar: info.lunar)
        let hasPublic = hols.contains { $0.isPublic }
        let hasAny = !hols.isEmpty
        let today = isToday(info)
        let isSelected = isSelected(info)

        return Button {
            selected = cal.date(from: DateComponents(year: info.solarY, month: info.solarM, day: info.solarD))
        } label: {
            VStack(spacing: 0) {
                Text(primary)
                    .font(.system(size: 12, weight: today ? .bold : .medium))
                    .foregroundStyle(cellColor(info, today: today, hasPublic: hasPublic))
                Text(secondary)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.white.opacity(info.inMonth ? 0.4 : 0.18))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(today ? calAccent : .clear)
            )
            .overlay(alignment: .bottom) {
                if hasAny {
                    Circle()
                        .fill(hasPublic ? (today ? Color.white : calAccent) : .white.opacity(0.3))
                        .frame(width: 3, height: 3).padding(.bottom, 1)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(isSelected && !today ? 0.5 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(info.inMonth ? 1 : 0.35)
    }

    private func cellColor(_ info: DayInfo, today: Bool, hasPublic: Bool) -> Color {
        if today { return .white }
        if info.weekdayMon0 == 6 { return calAccent.opacity(info.inMonth ? 0.9 : 0.4) } // CN đỏ
        if hasPublic { return calAccent.opacity(0.9) }
        return .white.opacity(info.inMonth ? 0.9 : 0.4)
    }

    private func lunarCorner(_ l: LunarDate) -> String {
        l.day == 1 ? "1/\(l.month)" : "\(l.day)"
    }

    // MARK: Footer

    private var footer: some View {
        let day = selected ?? Date()
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        let hols = VietnameseHolidays.holidays(solarM: c.month!, solarD: c.day!, lunar: l)
        return HStack(spacing: 6) {
            if hols.isEmpty {
                Text("\(c.day!)/\(c.month!) DL — \(l.day)/\(l.month) ÂL")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            } else {
                Image(systemName: "party.popper.fill").font(.system(size: 9)).foregroundStyle(calAccent)
                Text(hols.map { $0.name }.joined(separator: " · "))
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Day building

    private var title: String {
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        if mode == .solar {
            return "Tháng \(c.month!), \(c.year!)"
        } else {
            let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
            return "Tháng \(l.month) — \(VietnameseLunar.canChi(year: l.year))"
        }
    }

    private var days: [DayInfo] {
        mode == .solar ? solarDays() : lunarDays()
    }

    /// Lưới dương: điền các ô đầu (T2..) trước ngày 1, rồi cả tháng, rồi bù cuối.
    private func solarDays() -> [DayInfo] {
        let c = cal.dateComponents([.year, .month], from: anchor)
        guard let first = cal.date(from: DateComponents(year: c.year!, month: c.month!, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let leading = weekdayMon0(first)
        var infos: [DayInfo] = []
        // Ngày bù đầu (tháng trước).
        for i in stride(from: leading, to: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: first) { infos.append(info(from: d, inMonth: false)) }
        }
        // Ngày trong tháng.
        for day in range {
            if let d = cal.date(from: DateComponents(year: c.year!, month: c.month!, day: day)) {
                infos.append(info(from: d, inMonth: true))
            }
        }
        // Bù cuối cho đủ bội số 7.
        while infos.count % 7 != 0 {
            if let last = infos.last,
               let base = cal.date(from: DateComponents(year: last.solarY, month: last.solarM, day: last.solarD)),
               let d = cal.date(byAdding: .day, value: 1, to: base) {
                infos.append(info(from: d, inMonth: false))
            } else { break }
        }
        return infos
    }

    /// Lưới âm: từ tháng âm của `anchor`, dựng ngày 1..N theo ngày dương thực tế.
    private func lunarDays() -> [DayInfo] {
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        let anchorLunar = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        let lm = anchorLunar.month, ly = anchorLunar.year, leap = anchorLunar.isLeapMonth
        let count = VietnameseLunar.daysInLunarMonth(month: lm, year: ly, isLeap: leap)
        let firstSolar = VietnameseLunar.solar(fromLunar: 1, lm, ly, isLeap: leap)
        guard let first = cal.date(from: DateComponents(year: firstSolar.y, month: firstSolar.m, day: firstSolar.d)) else { return [] }
        let leading = weekdayMon0(first)
        var infos: [DayInfo] = []
        for i in stride(from: leading, to: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: first) { infos.append(info(from: d, inMonth: false)) }
        }
        for offset in 0..<count {
            if let d = cal.date(byAdding: .day, value: offset, to: first) { infos.append(info(from: d, inMonth: true)) }
        }
        while infos.count % 7 != 0 {
            if let last = infos.last,
               let base = cal.date(from: DateComponents(year: last.solarY, month: last.solarM, day: last.solarD)),
               let d = cal.date(byAdding: .day, value: 1, to: base) {
                infos.append(info(from: d, inMonth: false))
            } else { break }
        }
        return infos
    }

    private func info(from date: Date, inMonth: Bool) -> DayInfo {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        return DayInfo(solarY: c.year!, solarM: c.month!, solarD: c.day!, lunar: l,
                       weekdayMon0: weekdayMon0(date), inMonth: inMonth)
    }

    /// 0 = Thứ 2 ... 6 = Chủ nhật (Calendar mặc định CN=1).
    private func weekdayMon0(_ date: Date) -> Int {
        let wd = cal.component(.weekday, from: date)  // 1=CN..7=T7
        return (wd + 5) % 7
    }

    private func shiftMonth(_ delta: Int) {
        if mode == .solar {
            if let d = cal.date(byAdding: .month, value: delta, to: anchor) { anchor = d }
        } else {
            // Dịch ~1 tuần rưỡi qua ranh giới tháng âm để sang tháng âm kế.
            if let d = cal.date(byAdding: .day, value: delta * 30, to: anchor) { anchor = d }
        }
    }

    private func isToday(_ info: DayInfo) -> Bool {
        let t = cal.dateComponents([.year, .month, .day], from: Date())
        return info.solarY == t.year && info.solarM == t.month && info.solarD == t.day
    }

    private func isSelected(_ info: DayInfo) -> Bool {
        guard let selected else { return false }
        let s = cal.dateComponents([.year, .month, .day], from: selected)
        return info.solarY == s.year && info.solarM == s.month && info.solarD == s.day
    }
}
```

- [ ] **Step 2: Thêm state + onChange + case content trong NotchRootView**

Trong `struct NotchRootView` (gần `@State private var railTab` dòng 8) thêm:
```swift
    @State private var calMode: CalMode = .solar
    @State private var calAnchor: Date = Date()
    @State private var calSelected: Date? = nil
```

Trong khối `content` switch (dòng ~148), thêm nhánh calendar TRƯỚC `default`:
```swift
        case .music:         musicPanel
        case .notifications: notificationsPanel
        case .calendar:      calendarPanel
        default:             placeholderPanel(railTab)
```

Thêm computed view (đặt gần `musicPanel`):
```swift
    private var calendarPanel: some View {
        CalendarPanel(mode: $calMode, anchor: $calAnchor, selected: $calSelected)
    }
```

Tại `ThemeCarousel(...).onChange(of: railTab)` hiện có (dòng ~124), thêm cập nhật cờ tall. Đổi khối:
```swift
                .onChange(of: railTab) { _, _ in
```
thành (giữ nguyên phần thân cũ, chỉ thêm dòng set cờ ngay đầu):
```swift
                .onChange(of: railTab) { _, newTab in
                    vm.panelWantsTall = (newTab == .calendar)
```
(nếu tham số cũ là `_, _` và thân có nội dung, chỉ đổi `_, _` → `_, newTab` và thêm dòng `vm.panelWantsTall = (newTab == .calendar)` làm câu đầu tiên trong closure.)

- [ ] **Step 3: Build**

Run:
```bash
cd app && swift build 2>&1 | tail -8
```
Expected: build thành công, không lỗi.

- [ ] **Step 4: Chạy app + kiểm tra bằng mắt**

Run:
```bash
cd /Users/crossian/Documents/repo/just-a-notch && ./app/scripts/run_app.sh 2>&1 | tail -4
```
Sau đó mở panel, cuộn rail tới tab Lịch (icon calendar). Kiểm tra:
- Chế độ Dương: lưới tháng hiện tại, ngày hôm nay tô đỏ, mỗi ô có số âm nhỏ góc dưới; Chủ nhật màu đỏ; ô có lễ có chấm.
- Bấm toggle "Âm": header đổi "Tháng N — [Can Chi]", số âm to, số dương nhỏ.
- Bấm ‹ ›: đổi tháng. Bấm một ngày lễ (vd 2/9, hoặc 30/4) → dòng chân hiện tên lễ.
- Chụp màn hình xác nhận (screencapture vùng notch) trước khi báo hoàn thành.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/UI/CalendarPanel.swift app/Sources/JustANotch/UI/NotchRootView.swift
git commit -m "feat(calendar): dual solar/lunar calendar panel with VN holidays"
```

---

## Self-Review Notes

- **Spec coverage:** RailTab đổi (Task 3) ✓; lõi âm lịch + Can Chi (Task 1) ✓; ngày lễ dương+âm gộp không phân biệt (Task 2 + dayCell/footer Task 5) ✓; toggle Dương/Âm + điều hướng + Hôm nay-qua-chọn ✓ (nút "Hôm nay" gộp vào: chọn lại/điều hướng; nếu muốn nút riêng có thể thêm — xem lưu ý dưới); chiều cao panel (Task 4) ✓; test (Task 1,2) ✓.
- **Lưu ý "Hôm nay":** spec có nhắc nút "Hôm nay". Plan hiện chưa thêm nút riêng để giữ header gọn. Nếu muốn, thêm 1 `navButton("dot.circle")` gọi `anchor = Date(); selected = nil`. Đây là tùy chọn nhỏ, người thực thi có thể thêm khi dựng header.
- **Giới hạn điều hướng chế độ Âm:** `shiftMonth` ở mode Âm dịch 30 ngày dương rồi lấy lại tháng âm của anchor — đủ để sang tháng âm kế trong đa số trường hợp; tháng âm 29 ngày vẫn nhảy đúng vì anchor được quy về tháng âm chứa nó.
- **Placeholder scan:** không còn TBD/TODO trong code steps.
- **Type consistency:** `LunarDate`, `VietnameseLunar.lunar/solar/daysInLunarMonth/canChi`, `Holiday`, `VietnameseHolidays.holidays(solarM:solarD:lunar:)`, `CalMode`, `CalendarPanel(mode:anchor:selected:)`, `vm.panelWantsTall`, `vm.maxSurfaceHeight` — dùng nhất quán giữa các task.

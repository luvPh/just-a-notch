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

    /// Bộ nhớ đệm quy đổi Dương→Âm. Phép tính thiên văn (vòng lặp sunLongitude…) khá
    /// nặng và bị gọi ~42 lần mỗi lần dựng lưới; đệm lại giúp cuộn/đổi trang mượt,
    /// không nghẽn main thread. Khoá gói (year, month, day) vào một Int.
    private static var lunarCache: [Int: LunarDate] = [:]

    static func lunar(fromSolar year: Int, _ month: Int, _ day: Int) -> LunarDate {
        let key = (year * 100 + month) * 100 + day
        if let hit = lunarCache[key] { return hit }
        let result = computeLunar(fromSolar: year, month, day)
        lunarCache[key] = result
        return result
    }

    private static func computeLunar(fromSolar year: Int, _ month: Int, _ day: Int) -> LunarDate {
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

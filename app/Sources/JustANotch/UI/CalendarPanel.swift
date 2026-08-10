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
            // Dịch ~1 tháng âm qua ranh giới để sang tháng âm kế.
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

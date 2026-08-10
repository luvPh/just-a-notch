import SwiftUI

private let calAccent = Color(red: 0.96, green: 0.36, blue: 0.33)   // đỏ: hôm nay / CN
private let calHoliday = Color(red: 1.0, green: 0.82, blue: 0.32)   // vàng: ngày lễ

enum CalMode { case solar, lunar }

/// Một ô ngày trong lưới: mọi ô đều biết cả ngày dương lẫn ngày âm.
/// `id` ổn định theo ngày dương để SwiftUI giữ định danh ô qua các lần dựng
/// (mượt animation, không dựng lại toàn bộ mỗi frame).
private struct DayInfo: Identifiable {
    var id: String { "\(solarY)-\(solarM)-\(solarD)" }
    let solarY: Int, solarM: Int, solarD: Int
    let lunar: LunarDate
    let weekdayMon0: Int   // 0 = Thứ 2 ... 6 = Chủ nhật
    let inMonth: Bool      // thuộc tháng đang xem (mode-primary)
}

struct CalendarPanel: View {
    @Binding var mode: CalMode
    @Binding var anchor: Date          // ngày bất kỳ trong tháng đang xem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var toggleNS
    /// Ngày đang hover — điều khiển dòng chân (thay cho bấm chọn).
    @State private var hoveredDay: Date?
    /// Hướng lật trang gần nhất: +1 tiến (tương lai), −1 lùi (quá khứ).
    @State private var pageDir = 1

    private let cal = Calendar(identifier: .gregorian)
    private let weekdayLabels = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    // MARK: Springs (motion là trọng tâm của app)
    private var pageSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.44, dampingFraction: 0.82)
    }
    private var toggleSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.74)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            weekdayRow
            gridPager
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            navButton("chevron.left") { page(-1) }
            navButton("chevron.right") { page(1) }
            Text(title)
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                // Đổi tiêu đề mượt khi lật tháng / đổi chế độ.
                .contentTransition(.numericText())
                .animation(pageSpring, value: title)
            Spacer(minLength: 4)
            todayButton
            modeToggle
        }
    }

    private var todayButton: some View {
        Button { goToday() } label: {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(calAccent)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("Về hôm nay")
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleChip("Dương", isActive: mode == .solar) { setMode(.solar) }
            toggleChip("Âm", isActive: mode == .lunar) { setMode(.lunar) }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func toggleChip(_ label: String, isActive: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1).fixedSize()
                .foregroundStyle(isActive ? Color.black : .white.opacity(0.7))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background {
                    // Viên nền trắng TRƯỢT giữa hai chip (matchedGeometry).
                    if isActive {
                        Capsule().fill(.white.opacity(0.92))
                            .matchedGeometryEffect(id: "toggleKnob", in: toggleNS)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func navButton(_ system: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: system).font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 30, height: 28)   // vùng bấm rộng hơn
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayLabels, id: \.self) { d in
                Text(d).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(d == "CN" ? calAccent.opacity(0.75) : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid (có lật trang theo hướng)

    /// Bọc lưới trong một tầng clip, đổi `id` theo tháng+chế độ để kích hoạt
    /// transition trượt ngang theo `pageDir`.
    private var gridPager: some View {
        grid
            .id(monthKey)
            .transition(pageTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(alignment: .center) { yearWatermark }   // năm mờ sau lưới
            .clipShape(Rectangle())   // chặn transition tràn ra ngoài cột nội dung
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        // Trượt BIÊN ĐỘ NHỎ (không dùng .move toàn chiều rộng) để lưới không bao
        // giờ tràn sang rail; kết hợp mờ dần. `gridPager` vẫn clip an toàn.
        let dx: CGFloat = 26
        return .asymmetric(
            insertion: .offset(x: pageDir >= 0 ? dx : -dx).combined(with: .opacity),
            removal: .offset(x: pageDir >= 0 ? -dx : dx).combined(with: .opacity))
    }

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(days) { info in dayCell(info) }
        }
    }

    private func dayCell(_ info: DayInfo) -> some View {
        let primary = mode == .solar ? "\(info.solarD)" : "\(info.lunar.day)"
        let hols = VietnameseHolidays.holidays(solarM: info.solarM, solarD: info.solarD, lunar: info.lunar)
        let hasPublic = hols.contains { $0.isPublic }
        let hasHoliday = !hols.isEmpty
        // Chỉ nổi bật "hôm nay" khi ô thuộc tháng đang xem → tránh 2 ô đỏ chồng
        // nhau lúc lật (nhấp nháy) và khối đỏ xỉn ngoài tháng.
        let showToday = isToday(info) && info.inMonth
        let cellDate = cal.date(from: DateComponents(year: info.solarY, month: info.solarM, day: info.solarD))
        let hovered = isHovered(cellDate)

        return Text(primary)
            .font(.system(size: 13, weight: showToday || hasPublic ? .bold : .medium))
            .foregroundStyle(cellColor(info, today: showToday, hasHoliday: hasHoliday, hasPublic: hasPublic))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(showToday ? calAccent : (hovered ? .white.opacity(0.12) : .clear))
            )
            // Hover: phóng nhẹ + TRƯỢT LÊN về phía con trỏ (phản hồi tức thì).
            .scaleEffect(hovered ? 1.14 : 1.0)
            .offset(y: hovered ? -2 : 0)
            .zIndex(hovered ? 1 : 0)
            .opacity(info.inMonth ? 1 : 0.3)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
                    if inside { hoveredDay = cellDate }
                    else if isHovered(cellDate) { hoveredDay = nil }
                }
            }
    }

    private func cellColor(_ info: DayInfo, today: Bool, hasHoliday: Bool, hasPublic: Bool) -> Color {
        if today { return .white }                       // chữ trắng trên nền đỏ
        if hasHoliday { return hasPublic ? calHoliday : calHoliday.opacity(0.75) } // vàng: ngày lễ
        if info.weekdayMon0 == 6 { return calAccent.opacity(info.inMonth ? 0.9 : 0.4) } // CN đỏ
        return .white.opacity(info.inMonth ? 0.9 : 0.4)
    }

    // MARK: Footer

    private var footer: some View {
        let day = hoveredDay ?? Date()
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        let hols = VietnameseHolidays.holidays(solarM: c.month!, solarD: c.day!, lunar: l)
        // Đang ở lịch DƯƠNG → hiện ngày ÂM viết đầy đủ; ở lịch ÂM → hiện ngày DƯƠNG.
        let dateText = mode == .solar
            ? "\(l.day) tháng \(l.month)\(l.isLeapMonth ? " nhuận" : "") âm lịch"
            : "\(c.day!) tháng \(c.month!) dương lịch"
        return HStack(spacing: 6) {
            Text(dateText)
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            if !hols.isEmpty {
                Text("·").font(.system(size: 10)).foregroundStyle(.white.opacity(0.28))
                Image(systemName: "party.popper.fill").font(.system(size: 9)).foregroundStyle(calHoliday)
                Text(hols.map { $0.name }.joined(separator: " · "))
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(calHoliday)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Slide-in nhẹ từ dưới khi đổi ngày hover.
        .id(hoveredDay)
        .transition(.offset(y: 6).combined(with: .opacity))
    }

    // MARK: Titles & keys

    private var title: String {
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        if mode == .solar {
            return "Tháng \(c.month!)"
        } else {
            let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
            return "Tháng \(l.month)\(l.isLeapMonth ? " nhuận" : "")"
        }
    }

    /// Năm hiển thị mờ sau lưới: dương → số năm; âm → Can Chi.
    private var yearLabel: String {
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        if mode == .solar { return "\(c.year!)" }
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        return VietnameseLunar.canChi(year: l.year)
    }

    private var yearWatermark: some View {
        Text(yearLabel)
            .font(.system(size: 74, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.07))
            .lineLimit(1).minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
            .contentTransition(.numericText())
            .animation(pageSpring, value: yearLabel)
    }

    /// Định danh "trang" đang xem (đổi ⇒ transition lật). Gồm chế độ + tháng.
    private var monthKey: String {
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        if mode == .solar { return "S-\(c.year!)-\(c.month!)" }
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        return "L-\(l.year)-\(l.month)-\(l.isLeapMonth)"
    }

    // MARK: Day building

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
        for i in stride(from: leading, to: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: first) { infos.append(info(from: d, inMonth: false)) }
        }
        for day in range {
            if let d = cal.date(from: DateComponents(year: c.year!, month: c.month!, day: day)) {
                infos.append(info(from: d, inMonth: true))
            }
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

    // MARK: Navigation (mọi thay đổi tháng đều có motion + hướng)

    private func page(_ delta: Int) {
        pageDir = delta
        withAnimation(pageSpring) { shiftMonth(delta) }
    }

    private func goToday() {
        let now = Date()
        pageDir = now >= anchor ? 1 : -1   // chạy về hôm nay theo đúng hướng thời gian
        withAnimation(pageSpring) {
            anchor = now
            hoveredDay = nil
        }
    }

    private func setMode(_ m: CalMode) {
        guard m != mode else { return }
        pageDir = (m == .lunar) ? 1 : -1   // Âm ở bên phải toggle ⇒ trượt tới
        withAnimation(toggleSpring) { mode = m }
    }

    private func shiftMonth(_ delta: Int) {
        if mode == .solar {
            if let d = cal.date(byAdding: .month, value: delta, to: anchor) { anchor = d }
            return
        }
        // Chế độ Âm: nhảy theo ranh giới tháng âm THẬT (29/30 ngày), không ước lượng.
        let c = cal.dateComponents([.year, .month, .day], from: anchor)
        let al = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        let firstS = VietnameseLunar.solar(fromLunar: 1, al.month, al.year, isLeap: al.isLeapMonth)
        guard let first = cal.date(from: DateComponents(year: firstS.y, month: firstS.m, day: firstS.d)) else { return }
        if delta > 0 {
            let len = VietnameseLunar.daysInLunarMonth(month: al.month, year: al.year, isLeap: al.isLeapMonth)
            if let d = cal.date(byAdding: .day, value: len, to: first) { anchor = d }
        } else {
            if let d = cal.date(byAdding: .day, value: -1, to: first) { anchor = d }
        }
    }

    // MARK: Predicates

    private func isToday(_ info: DayInfo) -> Bool {
        let t = cal.dateComponents([.year, .month, .day], from: Date())
        return info.solarY == t.year && info.solarM == t.month && info.solarD == t.day
    }

    private func isHovered(_ date: Date?) -> Bool {
        guard let date, let hoveredDay else { return false }
        return cal.isDate(date, inSameDayAs: hoveredDay)
    }
}

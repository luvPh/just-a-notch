import SwiftUI
import AppKit

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
    /// false = xem tuần (mặc định, gọn), true = phóng ra lưới tháng.
    @Binding var expanded: Bool
    /// Báo số hàng tuần của tháng đang xem (để panel co/giãn đúng chiều cao lưới).
    var onRowsChange: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var toggleNS
    /// Ngày đang hover — điều khiển dòng chân (thay cho bấm chọn).
    @State private var hoveredDay: Date?
    /// Ngày đang nằm CHÍNH GIỮA dải tuần (nguồn sự thật khi cuộn carousel).
    @State private var centerDayID: String?
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
            if expanded {
                weekdayRow
                gridPager
                footer
            } else {
                weekPager
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reportRows() }
        .onChange(of: anchor) { _, _ in reportRows() }
        .onChange(of: mode) { _, _ in reportRows() }
    }

    /// Số hàng tuần của tháng đang xem (tổng ô ÷ 7) → báo ra ngoài để panel co lại.
    private func reportRows() {
        onRowsChange?(max(1, daysFor(anchor).count / 7))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            // Không còn nút ◀▶: tuần thì cuộn ngày, tháng thì trượt/cuộn để đổi tháng.
            Text(title)
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                // Đổi tiêu đề tức thì cho khớp với lưới (MonthPager nhảy ~ngay lập tức).
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.12), value: title)
            Spacer(minLength: 4)
            todayButton
            expandButton
            modeToggle
        }
    }

    /// Chuyển tuần ⇄ tháng. Icon phản ánh hành động kế tiếp.
    private var expandButton: some View {
        Button {
            withAnimation(toggleSpring) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left"
                                       : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(expanded ? "Thu về tuần" : "Xem cả tháng")
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

    /// Lưới tháng là SwiftUI THẬT (không bọc trong NSHostingView) nên đổi trang animate
    /// đầy đủ: mỗi tháng có `.id` riêng + `.push` transition theo hướng cuộn. Việc bắt
    /// con lăn/trackpad do `MonthScrollCatcher` (NSView trong suốt, click xuyên qua) lo,
    /// giống dải rail bên cạnh — nên bấm ô ngày tháng trước/sau vẫn hoạt động.
    private var gridPager: some View {
        ZStack(alignment: .top) {
            monthGrid(for: anchor)
                .id(monthKey(anchor))
                .transition(pageTransition)
        }
        // Chiều cao CỐ ĐỊNH theo số hàng ⇒ vùng cắt/nhận-chạm không "rung" khi lật trang,
        // nên các nút ở header luôn bấm được ngay cả trong lúc animation đang chạy.
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: gridHeight, alignment: .top)
        .background(alignment: .center) { yearWatermark }   // năm mờ sau lưới
        .background(
            MonthScrollCatcher { delta in
                pageDir = delta
                withAnimation(pageSpring) { anchor = steppedAnchor(anchor, delta) }
            }
        )
        .clipShape(Rectangle())
    }

    /// Trang mới trượt vào theo hướng thời gian (tiến → từ dưới lên, lùi → từ trên xuống).
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .push(from: pageDir > 0 ? .bottom : .top),
            removal: .push(from: pageDir > 0 ? .top : .bottom)
        )
    }

    /// Số hàng tuần & chiều cao lưới tương ứng (ô cao 28, cách nhau 2).
    private var gridRows: Int { max(1, daysFor(anchor).count / 7) }
    private var gridHeight: CGFloat { CGFloat(gridRows) * 28 + CGFloat(gridRows - 1) * 2 }

    private func monthGrid(for a: Date) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(daysFor(a)) { info in dayCell(info) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Week carousel (mặc định — gọn, today ở giữa)

    /// Dải ngày (± khoảng) để cuộn liên tục. Chỉ dựng mảng `Date` (rẻ); mỗi ô mới
    /// tính âm lịch khi LazyHStack thực sự hiện nó ra.
    private let weekSpan = 220
    private var weekDates: [Date] {
        let base = cal.startOfDay(for: Date())
        return (-weekSpan...weekSpan).compactMap { cal.date(byAdding: .day, value: $0, to: base) }
    }

    private func dayID(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    /// Carousel tuần thuần SwiftUI (giống dải rail `ThemeCarousel`): chỉ dựng các ô
    /// TRONG TẦM NHÌN, cuộn tự do rồi bắt dính vào ô giữa khi buông tay. Không còn
    /// dựng lại cả 441 ô mỗi lần vượt ranh giới ⇒ mượt 60fps, không tụt frame.
    private var weekPager: some View {
        GeometryReader { geo in
            WeekCarousel(dates: weekDates,
                         viewportWidth: geo.size.width,
                         centerID: Binding(get: { centerDayID },
                                           set: { centerDayID = $0; syncAnchor(to: $0) }),
                         idOf: dayID,
                         todayID: dayID(Date()),
                         reduceMotion: reduceMotion) { d, focus in
                AnyView(weekCell(info(from: d, inMonth: true), focus: focus))
            }
        }
        .frame(height: 62)
    }

    /// Ngày giữa dải đổi ⇒ đồng bộ `anchor` (để tiêu đề tháng + lưới tháng khớp).
    private func syncAnchor(to id: String?) {
        guard let d = date(fromID: id) else { return }
        anchor = d
    }

    private func date(fromID id: String?) -> Date? {
        guard let id else { return nil }
        let p = id.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// `focus`: 1 = đúng giữa carousel, giảm dần về 0 ở hai bên (liên tục theo vị trí
    /// cuộn) ⇒ phóng to/mờ dần mượt từng frame, không cần animation rời rạc.
    private func weekCell(_ info: DayInfo, focus: Double) -> some View {
        let primary = mode == .solar ? "\(info.solarD)" : "\(info.lunar.day)"
        let secondary = mode == .solar ? "\(info.lunar.day)/\(info.lunar.month)" : "\(info.solarD)/\(info.solarM)"
        let hols = VietnameseHolidays.holidays(solarM: info.solarM, solarD: info.solarD, lunar: info.lunar)
        let hasPublic = hols.contains { $0.isPublic }
        let hasHoliday = !hols.isEmpty
        let showToday = isToday(info)
        // Nền pill trắng chỉ hiện rõ khi ô về gần tâm.
        let pill = max(0, (focus - 0.5) / 0.5)
        let scale = reduceMotion ? 1 : 0.9 + 0.16 * focus
        let op = reduceMotion ? (focus > 0.5 ? 1.0 : 0.5) : 0.5 + 0.5 * focus

        return VStack(spacing: 2) {
            Text(weekdayLabels[info.weekdayMon0])
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(info.weekdayMon0 == 6 ? calAccent.opacity(0.7) : .white.opacity(0.4))
            Text(primary)
                .font(.system(size: 17, weight: showToday || hasPublic ? .bold : .semibold))
                .foregroundStyle(cellColor(info, today: showToday, hasHoliday: hasHoliday, hasPublic: hasPublic))
            Text(secondary)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(hasHoliday ? calHoliday.opacity(0.8) : .white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(showToday ? calAccent : .white.opacity(0.12 * pill))
        )
        // Ô về gần tâm phóng to & rõ dần (liên tục theo vị trí cuộn).
        .scaleEffect(scale)
        .opacity(op)
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
            .frame(height: 28)
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
            // Bấm ô ngoài tháng (tháng trước/sau) ⇒ nhảy sang tháng đó.
            .onTapGesture { if !info.inMonth, let d = cellDate { goToMonth(of: d) } }
    }

    private func goToMonth(of date: Date) {
        pageDir = date > anchor ? 1 : -1
        withAnimation(pageSpring) { anchor = date }
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

    /// Định danh "trang" tháng (đổi ⇒ MonthPager nhảy về trang giữa). Gồm chế độ + tháng.
    private func monthKey(_ a: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: a)
        if mode == .solar { return "S-\(c.year!)-\(c.month!)" }
        let l = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        return "L-\(l.year)-\(l.month)-\(l.isLeapMonth)"
    }

    // MARK: Day building

    private func daysFor(_ a: Date) -> [DayInfo] {
        mode == .solar ? solarDays(a) : lunarDays(a)
    }

    /// Lưới dương: điền các ô đầu (T2..) trước ngày 1, rồi cả tháng, rồi bù cuối.
    private func solarDays(_ a: Date) -> [DayInfo] {
        let c = cal.dateComponents([.year, .month], from: a)
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

    /// Lưới âm: từ tháng âm của `a`, dựng ngày 1..N theo ngày dương thực tế.
    private func lunarDays(_ a: Date) -> [DayInfo] {
        let c = cal.dateComponents([.year, .month, .day], from: a)
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

    private func goToday() {
        let now = Date()
        pageDir = now >= anchor ? 1 : -1   // chạy về hôm nay theo đúng hướng thời gian
        withAnimation(pageSpring) {
            anchor = now
            hoveredDay = nil
            if !expanded { centerDayID = dayID(now) }   // cuộn dải về hôm nay
        }
    }

    private func setMode(_ m: CalMode) {
        guard m != mode else { return }
        pageDir = (m == .lunar) ? 1 : -1   // Âm ở bên phải toggle ⇒ trượt tới
        withAnimation(toggleSpring) { mode = m }
    }

    /// Trả về `anchor` của tháng cách `a` đúng `delta` tháng (âm/dương chuẩn),
    /// không đổi state — dùng để dựng trang trước/sau cho MonthPager.
    private func steppedAnchor(_ a: Date, _ delta: Int) -> Date {
        if delta == 0 { return a }
        if mode == .solar {
            return cal.date(byAdding: .month, value: delta, to: a) ?? a
        }
        // Chế độ Âm: nhảy theo ranh giới tháng âm THẬT (29/30 ngày), không ước lượng.
        let c = cal.dateComponents([.year, .month, .day], from: a)
        let al = VietnameseLunar.lunar(fromSolar: c.year!, c.month!, c.day!)
        let firstS = VietnameseLunar.solar(fromLunar: 1, al.month, al.year, isLeap: al.isLeapMonth)
        guard let first = cal.date(from: DateComponents(year: firstS.y, month: firstS.m, day: firstS.d)) else { return a }
        if delta > 0 {
            let len = VietnameseLunar.daysInLunarMonth(month: al.month, year: al.year, isLeap: al.isLeapMonth)
            var d = cal.date(byAdding: .day, value: len, to: first) ?? a
            if delta > 1 { d = steppedAnchor(d, delta - 1) }
            return d
        } else {
            var d = cal.date(byAdding: .day, value: -1, to: first) ?? a
            if delta < -1 { d = steppedAnchor(d, delta + 1) }
            return d
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

// MARK: - Week carousel (thuần SwiftUI, giống dải rail)

/// Dải ngày cuộn ngang, dựng THEO KIỂU rail `ThemeCarousel`: `offset` là vị trí cuộn
/// liên tục (points); chỉ các ô trong tầm nhìn được dựng và đặt vị trí quanh tâm; ô
/// gần tâm nhất có `focus`≈1 (phóng to/rõ), xa dần thì mờ. Buông tay là bắt dính vào
/// ô giữa bằng spring. Không có NSScrollView, không dựng lại toàn dải ⇒ 60fps.
private struct WeekCarousel: View {
    let dates: [Date]
    let viewportWidth: CGFloat
    @Binding var centerID: String?
    let idOf: (Date) -> String
    let todayID: String
    var reduceMotion: Bool
    let cell: (Date, Double) -> AnyView   // focus 0…1

    @State private var offset: CGFloat = 0     // vị trí cuộn (points)
    @State private var scrollAcc: CGFloat = 0  // delta gom cho bước kế
    @State private var stepping = false        // cổng cooldown
    @State private var didInit = false

    private let stepThreshold: CGFloat = 6     // delta cần để sang 1 ngày
    private let stepCooldown: Double = 0.14    // tối thiểu giữa 2 bước khi cuộn dài
    private var cw: CGFloat { max(1, viewportWidth / 7) }

    private var stepSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.4, dampingFraction: 0.9)
    }

    var body: some View {
        let center = viewportWidth / 2
        let f = offset / cw                              // chỉ số tâm (thực)
        let mid = Int(f.rounded())
        let span = Int(ceil((viewportWidth / 2) / cw)) + 2
        let lo = max(0, mid - span)
        let hi = min(dates.count - 1, mid + span)

        ZStack {
            if hi >= lo {
                ForEach(lo...hi, id: \.self) { i in
                    let dx = CGFloat(i) - f
                    let x = center + dx * cw
                    let focus = Double(max(0, 1 - abs(dx) / 1.4))
                    // Mờ dần trước khi chạm mép để không có ô "cụt" tràn ra ngoài.
                    let room = center - abs(x - center)
                    let edge = Double(max(0, min(1, room / (cw * 0.5))))
                    cell(dates[i], focus)
                        .frame(width: cw)
                        .opacity(edge)
                        .position(x: x, y: 31)
                }
            }
        }
        .frame(width: viewportWidth, height: 62)
        .clipped()                                       // chặn ô hai bên tràn khỏi khung
        .contentShape(Rectangle())
        .background(
            HScrollCatcher(
                onScroll: { dy in handleScroll(dy) },
                onEnded: { scrollAcc = 0 }
            )
        )
        .onChange(of: viewportWidth) { _, _ in if !didInit { initOffset() } }
        .onAppear { initOffset() }
        .onChange(of: centerID) { _, id in syncFromOutside(id) }
    }

    private func initOffset() {
        guard viewportWidth > 0, !didInit else { return }
        didInit = true
        offset = CGFloat(index(of: centerID) ?? index(of: todayID) ?? 0) * cw
    }

    private func index(of id: String?) -> Int? {
        guard let id else { return nil }
        return dates.firstIndex { idOf($0) == id }
    }

    /// Gom delta → mỗi lần vượt ngưỡng sang ĐÚNG một ngày, có cooldown (giống rail):
    /// cuộn ít vẫn sang được, cuộn nhiều không nhảy vọt nhiều ngày một lúc.
    private func handleScroll(_ dy: CGFloat) {
        if scrollAcc != 0, (dy > 0) != (scrollAcc > 0) { scrollAcc = 0 }   // đổi chiều → bỏ tích cũ
        scrollAcc += dy
        guard !stepping, abs(scrollAcc) >= stepThreshold else { return }
        let dir = scrollAcc > 0 ? 1 : -1
        scrollAcc = 0
        stepping = true
        step(dir)
        DispatchQueue.main.asyncAfter(deadline: .now() + stepCooldown) { stepping = false }
    }

    private func step(_ dir: Int) {
        let cur = Int((offset / cw).rounded())
        let next = min(max(cur + dir, 0), dates.count - 1)
        guard next != cur else { return }
        withAnimation(stepSpring) { offset = CGFloat(next) * cw }
        let id = idOf(dates[next])
        if id != centerID { centerID = id }
    }

    /// centerID đổi từ NGOÀI (về hôm nay / đổi Âm-Dương) & lệch xa ⇒ trượt tới đó.
    private func syncFromOutside(_ id: String?) {
        guard let idx = index(of: id) else { return }
        let target = CGFloat(idx) * cw
        if abs(target - offset) > cw * 0.5 {
            withAnimation(stepSpring) { offset = target }
        }
    }
}

/// NSView trong suốt bắt con lăn/trackpad cho `WeekCarousel` (click xuyên qua), theo
/// đúng kiểu `ScrollWheelCatcher` của rail: bỏ pha quán tính (để momentum không tự
/// nhảy thêm ngày sau khi buông), báo `onScroll(dy)` khi ngón tay/con lăn còn chạy và
/// `onEnded()` để reset. Dùng local monitor vì panel là non-activating.
private struct HScrollCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher(); v.onScroll = onScroll; v.onEnded = onEnded; return v
    }
    func updateNSView(_ v: Catcher, context: Context) { v.onScroll = onScroll; v.onEnded = onEnded }

    final class Catcher: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // click rơi xuống ô ngày

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let win = self.window, e.window === win else { return e }
                let p = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return e }
                // Bỏ quán tính: chỉ pha do ngón tay/con lăn mới đổi ngày.
                if e.momentumPhase != [] {
                    if e.momentumPhase == .ended { self.onEnded?() }
                    return nil
                }
                let dy: CGFloat
                if e.hasPreciseScrollingDeltas {
                    dy = e.scrollingDeltaX != 0 ? e.scrollingDeltaX : e.scrollingDeltaY
                } else {
                    dy = (e.deltaX != 0 ? e.deltaX : e.deltaY) * 6
                }
                self.onScroll?(-dy)          // natural: nội dung đi theo ngón tay
                if e.phase == .ended || e.phase == .cancelled { self.onEnded?() }
                return nil                   // nuốt để panel bên cạnh không cuộn theo
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

// MARK: - Month scroll catcher (đổi tháng rời rạc, click xuyên qua)

/// NSView trong suốt nằm SAU lưới tháng, chỉ để BẮT con lăn/trackpad và đổi tháng —
/// không hề vẽ hay cuộn gì, và `hitTest` trả nil nên mọi cú bấm rơi thẳng xuống ô ngày
/// SwiftUI phía trên (giống `ScrollWheelCatcher` của rail). Nhờ lưới nằm trong cây
/// SwiftUI thật, đổi trang mới animate được đầy đủ.
///
/// Mỗi bước bị chặn bởi một khoảng COOLDOWN để lò xo `pageSpring` chạy trọn vẹn,
/// không bị cú cuộn kế tiếp cắt ngang → đổi tháng chậm & mượt, không "lướt" nhiều tháng.
private struct MonthScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void   // -1 lùi tháng, +1 tới tháng

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher(); v.onStep = onStep; return v
    }
    func updateNSView(_ v: Catcher, context: Context) { v.onStep = onStep }

    final class Catcher: NSView {
        var onStep: ((Int) -> Void)?
        private var monitor: Any?
        private var accum: CGFloat = 0
        private let threshold: CGFloat = 55            // px vuốt trackpad cho 1 tháng
        private var stepping = false                   // cổng cooldown: đợi animation xong
        private let cooldown: TimeInterval = 0.3       // ~ khớp thời lượng pageSpring

        // Không bao giờ chặn chuột — bấm ô ngày phải rơi xuống lưới SwiftUI.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // Panel là non-activating nên scrollWheel không tới qua responder chain; bắt
        // bằng local monitor (như rail), chỉ khi con trỏ thực sự nằm trên lưới.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let win = self.window, e.window === win else { return e }
                let p = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return e }
                self.handle(e)
                return nil   // nuốt sự kiện để panel bên cạnh không cuộn theo
            }
        }

        private func handle(_ event: NSEvent) {
            if !event.hasPreciseScrollingDeltas {
                // Con lăn chuột: mỗi nấc = đổi 1 tháng (có cooldown → không lướt nhanh).
                let d = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
                if d < 0 { fire(1) } else if d > 0 { fire(-1) }
                return
            }
            // Trackpad: chỉ tính pha do ngón tay (bỏ quán tính).
            guard event.momentumPhase == [] else { return }
            if event.phase == .began { accum = 0 }
            accum += event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            // Một cú vuốt vượt ngưỡng ⇒ đúng MỘT bước; phần dư reset (cooldown lo phần sau).
            if accum <= -threshold { accum = 0; fire(1) }
            else if accum >= threshold { accum = 0; fire(-1) }
            if event.phase == .ended || event.phase == .cancelled { accum = 0 }
        }

        /// Đổi đúng một tháng rồi khoá cho đến khi hết cooldown (để spring chạy trọn).
        private func fire(_ dir: Int) {
            guard !stepping else { return }
            stepping = true
            onStep?(dir)
            DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { [weak self] in
                self?.stepping = false
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

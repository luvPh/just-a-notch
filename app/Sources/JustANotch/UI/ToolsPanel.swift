import SwiftUI
import AppKit

// MARK: - Khung chung cho mọi tiện ích

/// Thêm tiện ích mới: thêm case vào `LauncherFeature` (icon, title, tint), khai báo
/// `short` / `subtitle` bên dưới, rồi viết phần thân trong `ToolsPanel.content` chỉ
/// bằng các khối dựng sẵn (`ToolStat`, `ToolPill`, `ToolRow`…). Header, quầng màu,
/// nền kính, ô chọn và hiệu ứng chuyển do khung lo — tiện ích nào cũng đồng bộ.
extension LauncherFeature {
    /// Nhãn ngắn dưới icon của ô.
    var short: String {
        switch self {
        case .calculator: return "Tính"
        case .gold:       return "Vàng"
        case .weather:    return "Trời"
        case .claude:     return "AI"
        }
    }
    /// Dòng mô tả dưới tên trong header thẻ.
    var subtitle: String {
        switch self {
        case .calculator: return "Gõ phép tính hoặc 100usd"
        case .gold:       return "Bảo Tín Mạnh Hải · đ/chỉ"
        case .weather:    return "Open-Meteo · cập nhật 30′"
        case .claude:     return "Phiên đang chạy và usage"
        }
    }
    /// Màu sáng (đầu gradient) — dùng cho icon, số nhấn, quầng.
    var light: Color { tint.first ?? .white }
    var gradient: LinearGradient {
        LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Ô tiện ích bên phải: kính mờ; khi chọn phủ màu nhẹ + viền gradient mảnh + quầng dưới + chấm.
struct ToolTile: View {
    let feature: LauncherFeature
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: feature.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(feature.light) : AnyShapeStyle(.ink.opacity(0.55)))
                    .scaleEffect(selected ? 1.1 : 1)
                Text(feature.short)
                    .font(.system(size: 9.5, weight: selected ? .bold : .medium))
                    .foregroundStyle(.ink.opacity(selected ? 1 : 0.4))
            }
            .frame(width: 54, height: 54)
            .background {
                ZStack {
                    shape.fill(.ink.opacity(hovering && !selected ? 0.09 : 0.05))
                    if selected {
                        shape.fill(LinearGradient(colors: [feature.light.opacity(0.32), (feature.tint.last ?? .white).opacity(0.12)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(selected
                    ? AnyShapeStyle(LinearGradient(colors: [feature.light, (feature.tint.last ?? .white).opacity(0.25)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(.ink.opacity(0.07)), lineWidth: 1)
            }
            // Đường sáng mảnh ở mép trên.
            .overlay(alignment: .top) {
                if selected {
                    Capsule().fill(.ink.opacity(0.35)).frame(width: 26, height: 1).padding(.top, 1)
                }
            }
            .shadow(color: (feature.tint.last ?? .clear).opacity(selected ? 0.55 : 0), radius: 9, y: 5)
            .offset(y: selected ? -1 : 0)
            .overlay(alignment: .bottom) {
                Circle().fill(feature.light).frame(width: 4, height: 4)
                    .offset(y: 8).opacity(selected ? 1 : 0)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(feature.title)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Thẻ nội dung: quầng màu góc trên trái, header (icon gradient, tên, mô tả, nhãn trực tiếp), thân.
struct ToolCard<Body: View>: View {
    let feature: LauncherFeature
    let meta: String?
    @ViewBuilder let content: () -> Body

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: feature.icon)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.ink)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(feature.gradient))
                    .overlay(alignment: .top) {
                        Capsule().fill(.ink.opacity(0.45)).frame(width: 16, height: 1).padding(.top, 1)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(feature.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.ink)
                    Text(feature.subtitle).font(.system(size: 10)).foregroundStyle(.ink.opacity(0.45))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let meta { ToolPill(text: meta) }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // Quầng nằm trong overlay của nền → không làm nền phình, cắt gọn theo thẻ.
            shape.fill(.ink.opacity(0.04))
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(RadialGradient(colors: [feature.light.opacity(0.22), .clear],
                                             center: .center, startRadius: 0, endRadius: 120))
                        .frame(width: 240, height: 240)
                        .offset(x: -110, y: -130)
                }
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(.ink.opacity(0.09), lineWidth: 0.5))
    }
}

/// Nhãn bo tròn nhỏ (thông tin trực tiếp, đơn vị, mã tiền…).
struct ToolPill: View {
    let text: String
    var icon: String?
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.ink.opacity(0.75))
        .padding(.horizontal, 8).frame(height: 20)
        .background(Capsule().fill(.ink.opacity(0.08)))
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else { label }
    }
}

/// Ô số liệu: nhãn nhỏ + số lớn (+ phần phụ tuỳ chọn như sparkline, % đổi).
struct ToolStat<Accessory: View>: View {
    let label: String
    let value: String
    var valueColor: Color = .ink
    var size: CGFloat = 15
    var trailing: String?
    var trailingColor: Color = .ink.opacity(0.5)
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.ink.opacity(0.45))
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(trailingColor)
                }
            }
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            accessory()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.ink.opacity(0.06), lineWidth: 0.5))
    }
}

extension ToolStat where Accessory == EmptyView {
    init(label: String, value: String, valueColor: Color = .ink, size: CGFloat = 15,
         trailing: String? = nil, trailingColor: Color = .ink.opacity(0.5)) {
        self.init(label: label, value: value, valueColor: valueColor, size: size,
                  trailing: trailing, trailingColor: trailingColor, accessory: { EmptyView() })
    }
}

/// Đường giá nhỏ có tô gradient bên dưới.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)),
                        y: g.size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + 1)
            }
            let line = Path { p in p.addLines(pts) }
            ZStack {
                Path { p in
                    p.addLines(pts)
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                    p.addLine(to: CGPoint(x: 0, y: g.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.4), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Vòng % nhỏ (usage).
struct ToolRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(.ink.opacity(0.1), lineWidth: 4)
            Circle().trim(from: 0, to: min(1, max(0.02, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }
}

// MARK: - Tab Tiện ích

/// Thẻ nội dung bên trái, lưới ô tiện ích 2 cột bên phải.
struct ToolsPanel: View {
    @ObservedObject var vm: NotchViewModel
    let reduceMotion: Bool
    @AppStorage("cfg.toolsPage") private var pageRaw = LauncherFeature.calculator.rawValue
    @AppStorage("calc.lastInput") private var calcInput = ""
    @ObservedObject private var gold = GoldPrices.shared
    @ObservedObject private var rates = CurrencyRates.shared
    @ObservedObject private var usage = AgentUsageStore.shared
    @ObservedObject private var weather = WeatherStore.shared

    private var page: LauncherFeature { LauncherFeature(rawValue: pageRaw) ?? .calculator }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolCard(feature: page, meta: meta(page)) { content(page) }
                .id(page)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))

            LazyVGrid(columns: [GridItem(.fixed(54), spacing: 8), GridItem(.fixed(54), spacing: 8)], spacing: 14) {
                ForEach(LauncherFeature.allCases) { f in
                    ToolTile(feature: f, selected: f == page) { pageRaw = f.rawValue }
                }
            }
            .frame(width: 116)
            .padding(.top, 2)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { gold.refresh(); usage.start(); rates.refreshIfStale(); weather.start() }
    }

    private func meta(_ f: LauncherFeature) -> String? {
        switch f {
        case .calculator: return rates.updatedAt.map { "tỷ giá \(Self.hm($0))" }
        case .gold:       return gold.world.map { Self.hm($0.at) }
        case .weather:    return weather.now.map { Self.hm($0.at) }
        case .claude:
            let n = vm.claudeSessions.filter(\.isActive).count
            return n > 0 ? "\(n) đang chạy" : nil
        }
    }

    @ViewBuilder private func content(_ f: LauncherFeature) -> some View {
        switch f {
        case .calculator: calculator
        case .gold:       goldBody
        case .weather:    WeatherToolBody()
        case .claude:     claudeBody
        }
    }

    // MARK: Máy tính

    private var calculator: some View {
        VStack(alignment: .leading, spacing: 8) {
            CalculatorView(onBack: {}, onInteract: { vm.noteInteraction() }, embedded: true, tint: page.light)
            HStack(spacing: 5) {
                ForEach(["usd", "eur", "jpy", "cny"], id: \.self) { c in
                    ToolPill(text: c.uppercased()) {
                        let t = calcInput.trimmingCharacters(in: .whitespaces)
                        calcInput = t.isEmpty ? "1\(c)" : "\(t) \(c)"
                    }
                }
            }
        }
    }

    // MARK: Giá vàng

    private var goldBody: some View {
        HStack(alignment: .top, spacing: 8) {
            if let w = gold.world {
                ToolStat(label: "XAU/USD", value: String(format: "$%.1f", w.price), size: 17,
                         trailing: w.changePct.map { String(format: "%+.2f%%", $0) },
                         trailingColor: (w.changePct ?? 0) >= 0 ? Color(red: 0.5, green: 0.85, blue: 0.6)
                                                                : Color(red: 1, green: 0.5, blue: 0.45)) {
                    if gold.intraday.count > 1 {
                        Sparkline(values: gold.intraday, color: page.light).frame(height: 26).padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 6) {
                ForEach(gold.local.prefix(2)) { l in
                    ToolStat(label: (l.code == "SJC9999" ? "SJC" : "Nhẫn") + " · bán",
                             value: Self.vnd(l.sell ?? l.buy), size: 13,
                             trailing: l.trend.flatMap { $0 == 0 ? nil : ($0 > 0 ? "▲" : "▼") },
                             trailingColor: (l.trend ?? 0) > 0 ? Color(red: 0.5, green: 0.85, blue: 0.6)
                                                               : Color(red: 1, green: 0.5, blue: 0.45))
                }
            }
            .frame(width: 128)
            if gold.world == nil && gold.local.isEmpty {
                Text(gold.loading ? "Đang tải giá…" : "Chưa lấy được giá vàng")
                    .font(.system(size: 11)).foregroundStyle(.ink.opacity(0.4))
            }
        }
    }

    // MARK: Claude & Codex

    private var claudeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ringStat(fraction: nil, color: page.light, label: "Claude · hôm nay",
                         value: usage.claude.map { UsageFormat.tokens($0.todayTokens) + " tok" } ?? "—")
                ringStat(fraction: usage.codex?.primary.map { $0.usedPercent / 100 },
                         color: Color(red: 0.62, green: 0.88, blue: 0.8), label: "Codex · 5 giờ",
                         value: usage.codex?.primary.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
            }
            let active = vm.claudeSessions.filter(\.isActive)
            if active.isEmpty {
                Text("Không có phiên nào đang chạy").font(.system(size: 10.5)).foregroundStyle(.ink.opacity(0.4))
            } else {
                VStack(spacing: 4) {
                    ForEach(active.prefix(2)) { s in
                        Button { ClaudeActivityStore.focus(s) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(s.agent == .claude ? page.light : Color(red: 0.62, green: 0.88, blue: 0.8))
                                    .frame(width: 6, height: 6)
                                Text(s.project).font(.system(size: 11, weight: .semibold)).foregroundStyle(.ink.opacity(0.9))
                                Text(s.state == .waiting ? "chờ duyệt" : (s.tool ?? "đang nghĩ"))
                                    .font(.system(size: 10)).foregroundStyle(.ink.opacity(0.45))
                                Spacer(minLength: 0)
                                if let t = s.turnStartedAt {
                                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                        Text(ClaudeFormat.duration(ctx.date.timeIntervalSince(t)))
                                            .font(.system(size: 10, design: .rounded)).monospacedDigit()
                                            .foregroundStyle(.ink.opacity(0.45))
                                    }
                                }
                            }
                            .lineLimit(1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func ringStat(fraction: Double?, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 9) {
            if let fraction { ToolRing(fraction: fraction, color: color) }
            else {
                Image(systemName: "sparkle").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(color.opacity(0.14)))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.ink.opacity(0.45))
                Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.ink)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.ink.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: Format

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "HH:mm dd/MM"
        return f.string(from: d)
    }

    private static func vnd(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "."; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
}

// MARK: - Thời tiết

/// Thân tiện ích Thời tiết: nhiệt độ lớn + tình trạng, cao/thấp, 6 giờ tới, đổi thành phố,
/// công tắc "Notch theo thời tiết".
struct WeatherToolBody: View {
    @ObservedObject private var store = WeatherStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let sky = Color(red: 0.55, green: 0.85, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let w = store.now {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: w.kind.symbol(day: w.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                        .frame(width: 34)
                    Text("\(Int(w.temp.rounded()))°")
                        .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.kind.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.ink.opacity(0.9))
                        Text("Cảm giác \(Int(w.feels.rounded()))° · \(Int(w.hi.rounded()))°/\(Int(w.lo.rounded()))°"
                             + (w.rainChance.map { " · mưa \($0)%" } ?? ""))
                            .font(.system(size: 9.5)).foregroundStyle(.ink.opacity(0.5)).monospacedDigit()
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    controls
                }
                hourly(w)
            } else {
                Text(store.loading ? "Đang tải thời tiết…" : (store.failed ? "Không lấy được thời tiết cho “\(store.city)”" : "Chưa có dữ liệu"))
                    .font(.system(size: 11)).foregroundStyle(.ink.opacity(0.45))
            }
            if store.now == nil { controls }
        }
        .onAppear { store.start() }
    }

    /// Nút thành phố + Notch theo trời — xếp dọc ở góc phải để thẻ không thêm hàng.
    private var controls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if editing {
                TextField("Tên thành phố", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.ink)
                    .focused($focused)
                    .padding(.horizontal, 8).frame(width: 130, height: 20)
                    .background(Capsule().fill(.ink.opacity(0.1)))
                    .onSubmit { commit() }
                    .onExitCommand { editing = false }
            } else {
                ToolPill(text: store.now?.city ?? store.city, icon: "mappin.and.ellipse") {
                    draft = store.city; editing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                }
            }
            ToolPill(text: settings.weatherAmbient ? "Notch theo trời: bật" : "Notch theo trời: tắt",
                     icon: settings.weatherAmbient ? "sparkles" : "circle.slash") {
                withAnimation(.easeInOut(duration: 0.5)) { settings.weatherAmbient.toggle() }
            }
            }
    }

    private func hourly(_ w: WeatherNow) -> some View {
        HStack(spacing: 0) {
            ForEach(w.hourly) { h in
                VStack(spacing: 2) {
                    Text(h.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 9)).foregroundStyle(.ink.opacity(0.45))
                    Image(systemName: h.kind.symbol(day: h.isDay))
                        .symbolRenderingMode(.multicolor).font(.system(size: 11))
                        .frame(height: 13)
                    Text("\(Int(h.temp.rounded()))°").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.ink.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(0.05)))
    }

    private func commit() {
        let c = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { store.city = c }
        editing = false
    }
}

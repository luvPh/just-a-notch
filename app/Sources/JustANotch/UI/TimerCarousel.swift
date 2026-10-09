import SwiftUI

// Tab Timer: hai cột. Trái = danh sách chế độ (Hẹn giờ nhanh, Pomodoro, Chuỗi,
// Nhắc nghỉ) kèm trạng thái sống; phải = nội dung chế độ đang chọn. Lăn chuột
// trên cột trái để đổi chế độ. Nút ⚙️ ở chân cột trái mở cài đặt hẹn giờ chung.
struct TimerCarousel: View {
    @ObservedObject var single: TimerService
    @ObservedObject var sequence: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var showingSettings: Bool
    // Panel cao 300px khi đang sửa chuỗi (tab 3). Do NotchViewModel sở hữu.
    @Binding var tall: Bool
    var onPreviewBreak: () -> Void = {}

    // Khoá đổi chế độ khi đang ở một màn setting con của trang hiện tại.
    @State private var locked = false
    @State private var acc: CGFloat = 0
    @State private var stepping = false
    @State private var hoveredMode: Int?

    private static let modes: [(title: String, icon: String)] = [
        ("Hẹn giờ nhanh", "timer"),
        ("Nhịp", "circle.dashed.inset.filled"),
        ("Nhắc nghỉ", "drop.fill"),
    ]
    private var pageCount: Int { Self.modes.count }
    private var page: Int { min(pageCount - 1, max(0, settings.timerPage)) }

    var body: some View {
        Group {
            if showingSettings {
                TimerGeneralSettings(settings: settings, onBack: { showingSettings = false })
            } else {
                HStack(alignment: .top, spacing: 14) {
                    sidebar
                    page(page)
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97)),
                            removal: .opacity))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .notchGlass()
                }
                .animation(.spring(response: 0.36, dampingFraction: 0.88), value: page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<pageCount, id: \.self) { i in modeRow(i) }
            Spacer(minLength: 0)
            Button { showingSettings = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape.fill").font(.system(size: 10, weight: .semibold))
                    Text("Cài đặt hẹn giờ").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.ink.opacity(0.45))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 168)
        .background {
            ScrollWheelCatcher(onScroll: handleScroll, onEnded: { acc = 0 })
        }
    }

    private func modeRow(_ i: Int) -> some View {
        let selected = i == page
        let m = Self.modes[i]
        let (sub, live) = status(i)
        return Button { go(to: i) } label: {
            HStack(spacing: 9) {
                Image(systemName: m.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : .ink.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? NotchTheme.accent : .ink.opacity(0.08)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.title).font(.system(size: 11.5, weight: selected ? .bold : .medium))
                        .foregroundStyle(.ink.opacity(selected ? 1 : 0.8))
                    Text(sub).font(.system(size: 9.5, weight: live ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(live ? NotchTheme.accent : .ink.opacity(0.4))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ink.opacity(selected ? 0.1 : (hoveredMode == i ? 0.05 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hoveredMode = h ? i : (hoveredMode == i ? nil : hoveredMode) }
    }

    /// Dòng phụ dưới tên chế độ; `live` = đang chạy (tô màu nhấn).
    private func status(_ i: Int) -> (String, Bool) {
        func clock(_ t: TimerService) -> String {
            let s = max(0, Int(t.remaining.rounded())); return String(format: "%02d:%02d", s / 60, s % 60)
        }
        switch i {
        case 0: return single.isRunning ? ("Còn \(clock(single))", true)
                     : single.remaining > 0 ? ("Tạm dừng · \(clock(single))", false) : ("Đếm ngược một lần", false)
        case 1:
            if sequence.isRunning { return ("\(sequence.currentSegmentName) · \(clock(sequence))", true) }
            if !sequence.runSegments.isEmpty, sequence.remaining > 0 { return ("Tạm dừng · \(clock(sequence))", false) }
            return ("Pomodoro & chuỗi tự tạo", false)
        default:
            guard settings.breakReminderOn else { return ("Đang tắt", false) }
            if let next = BreakSchedule.slots(on: Date()).first(where: { $0 > Date() }) {
                return ("Lượt kế \(next.formatted(date: .omitted, time: .shortened))", false)
            }
            return ("Bật · hết lượt hôm nay", false)
        }
    }

    private func go(to i: Int) {
        guard !locked, i != page else { return }
        settings.timerPage = i
    }

    @ViewBuilder
    private func page(_ i: Int) -> some View {
        switch i {
        case 0: TimerPanel(timer: single, settings: settings, locked: $locked)
        case 1: FlowPage(timer: sequence, settings: settings, locked: $locked, tall: $tall)
        default: BreakReminderPage(settings: settings, onPreview: onPreviewBreak)
        }
    }

    // Lăn trên cột trái → đổi chế độ (kẹp 0…3, không vòng).
    private func handleScroll(_ dy: CGFloat) {
        guard !locked else { return }
        if acc != 0, (dy > 0) != (acc > 0) { acc = 0 }
        acc += dy
        guard !stepping, abs(acc) >= 4 else { return }
        let next = min(pageCount - 1, max(0, page + (acc > 0 ? 1 : -1)))
        acc = 0
        stepping = true
        go(to: next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { stepping = false }
    }
}

// MARK: - Nhắc nghỉ (chuyển từ Cài đặt sang)

struct BreakReminderPage: View {
    @ObservedObject var settings: AppSettings
    let onPreview: () -> Void

    private let water = Color(red: 0.40, green: 0.75, blue: 1.0)

    var body: some View {
        TimerPageLayout {
            // Cùng cỡ + cùng nét với OrbitClock để hai trang trùng tâm, trùng vòng.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let (frac, label, sub) = progress(ctx.date)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [water.opacity(settings.breakReminderOn ? 0.2 : 0.06), .clear],
                                             center: .center, startRadius: 4, endRadius: 70))
                    Circle()
                        .stroke(.ink.opacity(0.12), style: StrokeStyle(lineWidth: 3, dash: [0.8, 5.2]))
                        .padding(12 + 3.5)
                    Circle().stroke(water.opacity(0.18), lineWidth: 7)
                    Circle().trim(from: 0, to: settings.breakReminderOn ? max(0.001, frac) : 0)
                        .stroke(water, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .shadow(color: water.opacity(0.8), radius: 5)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: frac)
                    VStack(spacing: 0) {
                        Image(systemName: "drop.fill").font(.system(size: 11)).foregroundStyle(water)
                        Text(label).font(.system(size: 25, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.ink)
                        Text(sub).font(.system(size: 9.5, weight: .bold)).tracking(0.4).foregroundStyle(water)
                    }
                }
                .padding(3.5)
                .opacity(settings.breakReminderOn ? 1 : 0.55)
            }
        } info: {
            TimerPageHeading(title: "Nhắc đứng dậy · uống nước",
                             subtitle: "T2–T6 · 9:30–17:30 · nghỉ trưa & lễ")
            VStack(alignment: .leading, spacing: 4) {
                row("figure.stand", "Nhắc mỗi 30 phút") {
                    Toggle("", isOn: $settings.breakReminderOn).labelsHidden().toggleStyle(GlowToggleStyle())
                }
                row("bell.fill", "Âm báo") {
                    NotchSlider(value: $settings.breakVolume).frame(width: 90)
                        .disabled(!settings.breakSoundOn).opacity(settings.breakSoundOn ? 1 : 0.4)
                    Toggle("", isOn: $settings.breakSoundOn).labelsHidden().toggleStyle(GlowToggleStyle())
                }
            }
            HStack(spacing: 6) {
                pill("Nghe thử", "play.fill") { BreakChime.play(volume: Float(settings.breakVolume)) }
                pill("Xem lời nhắc", "eye.fill", action: onPreview)
            }
        }
        .help("Rời máy quá 5 phút hoặc app đang full màn hình thì bỏ lượt")
        .animation(.easeOut(duration: 0.2), value: settings.breakReminderOn)
    }

    /// (phần đã qua của khoảng 30′ tới lượt kế, chữ giữa, chữ phụ).
    private func progress(_ now: Date) -> (Double, String, String) {
        guard settings.breakReminderOn else { return (0, "Tắt", "nhắc nghỉ") }
        guard let next = BreakSchedule.slots(on: now).first(where: { $0 > now }) else {
            return (1, "Xong", "hết lượt hôm nay")
        }
        let left = next.timeIntervalSince(now)
        let span = Double(BreakSchedule.intervalMinutes * 60)
        let mins = Int((left / 60).rounded(.up))
        return (left > span ? 0 : 1 - left / span,
                left > span ? next.formatted(date: .omitted, time: .shortened) : "\(mins)′",
                left > span ? "lượt đầu" : "tới lượt kế")
    }

    private func row<C: View>(_ icon: String, _ title: String, @ViewBuilder trailing: () -> C) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.ink.opacity(0.6)).frame(width: 16)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.ink.opacity(0.9))
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 22)
    }

    private func pill(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.ink.opacity(0.85))
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(.ink.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

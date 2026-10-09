import SwiftUI

// Trang "Nhịp" của tab Timer: Pomodoro + chuỗi tự tạo gộp làm một. Pomodoro là
// một chuỗi dựng sẵn (sinh từ cấu hình), chuỗi tự tạo nằm cạnh nó trong dải chọn.
// Tất cả chạy trên cùng một TimerService và hiện bằng đồng hồ vòng chặng (OrbitClock).
struct FlowPage: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var locked: Bool
    @Binding var tall: Bool
    @StateObject private var store = SequenceStore()

    @AppStorage("cfg.flowSelected") private var selectedRaw = TimerSequence.pomodoroID.uuidString
    @State private var editing: TimerSequence?
    @State private var configuringPomo = false

    private var pomodoro: TimerSequence { .pomodoro(settings.pomodoroConfig, sound: settings.timerSoundName) }
    private var presets: [TimerSequence] { [pomodoro] + store.all }
    private var selected: TimerSequence { presets.first { $0.id.uuidString == selectedRaw } ?? pomodoro }
    private var isPomodoro: Bool { selected.id == TimerSequence.pomodoroID }

    /// Đang có phiên (chạy hoặc tạm dừng giữa chừng).
    private var inSession: Bool { !timer.runSegments.isEmpty && (timer.isRunning || timer.remaining > 0) }
    private var plan: [TimerSegment] { inSession ? timer.runSegments : flatten(selected) }
    private var index: Int { inSession ? timer.segIndex : 0 }
    private var segFraction: Double {
        guard inSession, timer.phaseLength > 0 else { return 0 }
        return min(1, max(0, 1 - timer.remaining / timer.phaseLength))
    }
    private var shownSeconds: Int {
        if inSession { return max(0, Int(timer.remaining.rounded())) }
        return (plan.first?.minutes ?? 0) * 60
    }

    var body: some View {
        Group {
            if let seq = editing {
                SequenceEditor(seq: seq, accent: NotchTheme.accent,
                               onSave: { store.save($0); selectedRaw = $0.id.uuidString; editing = nil },
                               onCancel: { editing = nil })
                    .padding(10)
            } else if configuringPomo {
                pomodoroConfig.padding(10)
            } else {
                main
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: editing != nil) { _, v in locked = v || configuringPomo; tall = v }
        .onChange(of: configuringPomo) { _, v in locked = v || editing != nil }
        .onDisappear { locked = false; tall = false }
    }

    // MARK: Main

    private var main: some View {
        TimerPageLayout {
            OrbitClock(plan: plan, index: index, fraction: segFraction, seconds: shownSeconds,
                       running: timer.isRunning, finished: timer.justFinished)
        } info: {
            TimerPageHeading(title: inSession ? (timer.label.isEmpty ? selected.name : timer.label) : selected.name,
                             subtitle: subtitle)
            controls
            presetStrip
        }
    }

    private var subtitle: String {
        if timer.justFinished { return "Hoàn thành cả chuỗi 🎉" }
        let total = plan.reduce(0) { $0 + $1.minutes }
        let left = plan.dropFirst(index + 1).reduce(0) { $0 + $1.minutes } + (shownSeconds + 59) / 60
        if inSession { return "Chặng \(index + 1)/\(plan.count) · còn ~\(left)′ tổng" }
        return "\(plan.count) chặng · \(total / 60 > 0 ? "\(total / 60)g " : "")\(total % 60)′"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            let color = plan.indices.contains(index) ? Color(hex: plan[index].colorHex) : NotchTheme.accent
            timerPrimary(running: timer.isRunning, color: color, playPause)
            timerCtl("forward.end.fill", help: "Sang chặng kế") { timer.skip() }
                .disabled(!inSession).opacity(inSession ? 1 : 0.4)
            timerCtl("arrow.counterclockwise", help: "Về đầu") { timer.reset() }
            Rectangle().fill(.ink.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 1)
            timerCtl(isPomodoro ? "slider.horizontal.3" : "pencil", help: isPomodoro ? "Cấu hình Pomodoro" : "Sửa chuỗi") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if isPomodoro { configuringPomo = true } else { editing = selected }
                }
            }
            if !isPomodoro {
                timerCtl("trash", help: "Xoá chuỗi") {
                    store.delete(selected.id); selectedRaw = TimerSequence.pomodoroID.uuidString
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: timer.isRunning)
    }

    private var presetStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(presets) { p in
                    let on = p.id == selected.id
                    Button {
                        guard !inSession else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedRaw = p.id.uuidString }
                    } label: {
                        HStack(spacing: 4) {
                            if p.id == TimerSequence.pomodoroID { Image(systemName: "leaf.fill").font(.system(size: 8)) }
                            Text(p.name).font(.system(size: 10, weight: on ? .bold : .medium))
                        }
                        .foregroundStyle(on ? Color.inkInverse : .ink.opacity(inSession ? 0.35 : 0.75))
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(on ? .ink.opacity(0.9) : .ink.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                if !store.isFull {
                    Button { editing = newSequence() } label: {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.ink.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.ink.opacity(0.08)))
                    }
                    .buttonStyle(.plain).help("Tạo chuỗi mới")
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .background(VerticalWheelToHorizontal())
    }

    private func playPause() {
        if timer.justFinished { timer.dismissFinished(); timer.reset() }
        if timer.isRunning { timer.pause() }
        else if inSession { timer.resume() }
        else {
            timer.startSequence(flatten(selected), label: selected.name,
                                autoAdvance: isPomodoro ? settings.pomoAutoStart : true)
        }
    }

    private func newSequence() -> TimerSequence {
        TimerSequence(id: UUID(), name: "Chuỗi \(store.all.count + 1)",
                      segments: [TimerSegment(id: UUID(), name: "Đoạn 1", minutes: 25,
                                              soundName: settings.timerSoundName, colorHex: "#5DCAA5")],
                      loopStart: nil, loopEnd: nil, loopCount: 1)
    }

    // MARK: Pomodoro config

    private var pomodoroConfig: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                backButton { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { configuringPomo = false } }
                Text("Cấu hình Pomodoro").font(.system(size: 11.5, weight: .bold)).foregroundStyle(.ink.opacity(0.9))
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 5) {
                stepRow("Làm", $settings.pomoWorkMinutes, 1...120, "′")
                stepRow("Nghỉ ngắn", $settings.pomoShortMinutes, 1...60, "′")
                stepRow("Nghỉ dài", $settings.pomoLongMinutes, 1...60, "′")
                stepRow("Số vòng", $settings.pomoRounds, 1...12, "")
            }
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.ink.opacity(0.7)).frame(width: 18)
                Text("Tự chạy chặng kế").font(.system(size: 11.5)).foregroundStyle(.ink.opacity(0.9))
                Spacer(minLength: 0)
                Toggle("", isOn: $settings.pomoAutoStart).labelsHidden().toggleStyle(GlowToggleStyle())
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.05)))
        }
    }

    private func stepRow(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ suffix: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.ink.opacity(0.7))
            Spacer(minLength: 0)
            Text("\(value.wrappedValue)\(suffix)").font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.ink).monospacedDigit()
            Stepper("", value: value, in: range).labelsHidden().fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.05)))
    }
}

// MARK: - Orbit clock

/// Đồng hồ vòng chặng: mỗi chặng một cung (dài theo số phút, màu riêng). Chặng đã
/// qua sáng đặc, chặng hiện tại tô dần kèm đầu sao phát sáng, chặng sau mờ. Ở giữa:
/// số đếm ngược lăn số + tên chặng; nền toả quầng màu chặng, "thở" khi đang chạy.
struct OrbitClock: View {
    let plan: [TimerSegment]
    let index: Int
    let fraction: Double
    let seconds: Int
    let running: Bool
    let finished: Bool

    @State private var breathe = false

    private var current: TimerSegment? { plan.indices.contains(index) ? plan[index] : nil }
    private var color: Color { finished ? Color(hex: "#4DD185") : Color(hex: current?.colorHex ?? "#F25C54") }

    /// (bắt đầu, kết thúc) của từng cung trên vòng 0…1, chừa khe giữa các cung.
    private var arcs: [(Double, Double)] {
        let total = Double(max(1, plan.reduce(0) { $0 + max(1, $1.minutes) }))
        let gap = plan.count > 1 ? min(0.012, 0.3 / Double(plan.count)) : 0
        var cum = 0.0
        return plan.map { s in
            let a = cum / total, b = (cum + Double(max(1, s.minutes))) / total
            cum += Double(max(1, s.minutes))
            return (a + gap / 2, max(a + gap / 2, b - gap / 2))
        }
    }

    var body: some View {
        let lw: CGFloat = 7
        ZStack {
            // Quầng màu chặng hiện tại.
            Circle()
                .fill(RadialGradient(colors: [color.opacity(running ? 0.35 : 0.18), .clear],
                                     center: .center, startRadius: 4, endRadius: 70))
                .scaleEffect(breathe && running ? 1.08 : 0.94)
                .animation(running ? .easeInOut(duration: 2.4).repeatForever(autoreverses: true) : .easeOut(duration: 0.4),
                           value: breathe && running)
            // Mặt số: vạch phút mảnh.
            Circle()
                .stroke(.ink.opacity(0.12), style: StrokeStyle(lineWidth: 3, dash: [0.8, 5.2]))
                .padding(lw + 5)
            // Các cung chặng.
            ForEach(Array(arcs.enumerated()), id: \.offset) { i, r in
                let c = Color(hex: plan[i].colorHex)
                Circle().trim(from: r.0, to: r.1)
                    .stroke(c.opacity(i < index || finished ? 0.85 : 0.18),
                            style: StrokeStyle(lineWidth: lw, lineCap: .round))
                if i == index && !finished {
                    let end = r.0 + (r.1 - r.0) * fraction
                    Circle().trim(from: r.0, to: end)
                        .stroke(c, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        .shadow(color: c.opacity(0.8), radius: 5)
                    // Đầu sao.
                    GeometryReader { g in
                        let r = min(g.size.width, g.size.height) / 2
                        let a = end * 2 * .pi
                        Circle().fill(.white)
                            .frame(width: lw + 3, height: lw + 3)
                            .shadow(color: c, radius: 6).shadow(color: c, radius: 2)
                            .position(x: g.size.width / 2 + r * cos(a), y: g.size.height / 2 + r * sin(a))
                    }
                    .opacity(fraction > 0 ? 1 : 0)
                }
            }
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: fraction)

            VStack(spacing: 0) {
                if finished {
                    Image(systemName: "checkmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 25, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.35), value: seconds)
                }
                Text(finished ? "Xong" : (current?.name ?? ""))
                    .font(.system(size: 9.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(color)
                    .lineLimit(1).frame(maxWidth: 76)
                    .contentTransition(.opacity)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
        }
        .padding(lw / 2)
        .onAppear { breathe = true }
    }
}

extension Color {
    /// "#RRGGBB" → Color (sai định dạng → trắng).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

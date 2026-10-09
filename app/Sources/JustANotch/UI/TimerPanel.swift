import SwiftUI

/// Khung chung cho mọi trang của tab Timer: mặt tròn cố định bên trái (cùng tâm ở
/// mọi trang), cột thông tin + nút căn trái bên phải.
struct TimerPageLayout<Dial: View, Info: View>: View {
    @ViewBuilder let dial: () -> Dial
    @ViewBuilder let info: () -> Info

    static var dialSize: CGFloat { 124 }
    /// Nội dung cột thông tin phải vừa chiều rộng này.
    static var infoWidth: CGFloat { 226 }

    var body: some View {
        // Cụm (mặt tròn + cột thông tin) rộng cố định, đặt giữa thẻ → hai bên cân,
        // và mặt tròn trùng tâm ở mọi trang.
        HStack(alignment: .center, spacing: 22) {
            dial().frame(width: Self.dialSize, height: Self.dialSize)
            VStack(alignment: .leading, spacing: 8) { info() }
                .frame(width: Self.infoWidth, alignment: .leading)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Bấm chỗ trống trong thẻ → rời ô nhập (không bị kẹt focus).
        .contentShape(Rectangle())
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}

/// Tiêu đề + dòng phụ dùng chung đầu cột thông tin.
struct TimerPageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.ink)
            Text(subtitle).font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.ink.opacity(0.45))
                .contentTransition(.numericText())
        }
        .lineLimit(1)
    }
}

/// Nút tròn phụ (nền mờ) dùng chung.
func timerCtl(_ name: String, help: String = "", _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: name).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.ink.opacity(0.85))
            .frame(width: 28, height: 28)
            .background(Circle().fill(.ink.opacity(0.08)))
    }
    .buttonStyle(.plain).help(help)
}

/// Nút chính (chạy/tạm dừng) tô màu, toả sáng khi đang chạy.
func timerPrimary(running: Bool, color: Color, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: running ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 34, height: 34)
            .background(Circle().fill(color).shadow(color: color.opacity(0.6), radius: running ? 8 : 0))
    }
    .buttonStyle(.plain)
}

// Trang "Hẹn giờ nhanh": đếm ngược một lần, dùng chung mặt OrbitClock (một cung).
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var locked: Bool

    @AppStorage("cfg.quickMinutes") private var minutes = 15
    @State private var message = ""
    @FocusState private var messageFocused: Bool

    private static let color = "#FF9F43"
    private static let presets = [5, 15, 25, 45]

    /// Đang có phiên (chạy hoặc tạm dừng).
    private var inSession: Bool { timer.isRunning || timer.remaining > 0 }
    private var seconds: Int { inSession ? max(0, Int(timer.remaining.rounded())) : minutes * 60 }
    private var fraction: Double {
        guard inSession, timer.phaseLength > 0 else { return 0 }
        return min(1, max(0, 1 - timer.remaining / timer.phaseLength))
    }
    private var plan: [TimerSegment] {
        let m = inSession ? max(1, Int((timer.phaseLength / 60).rounded())) : minutes
        return [TimerSegment(id: TimerSequence.pomodoroID, name: timer.label.isEmpty ? "Hẹn giờ" : timer.label,
                             minutes: m, soundName: "", colorHex: Self.color)]
    }

    var body: some View {
        TimerPageLayout {
            OrbitClock(plan: plan, index: 0, fraction: fraction, seconds: seconds,
                       running: timer.isRunning, finished: timer.justFinished)
        } info: {
            TimerPageHeading(title: timer.justFinished ? (timer.label.isEmpty ? "Hết giờ!" : timer.label) : "Hẹn giờ nhanh",
                             subtitle: subtitle)
            HStack(spacing: 8) {
                if timer.justFinished {
                    Button { timer.dismissFinished(); timer.reset() } label: {
                        Text("OK").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 20).frame(height: 30)
                            .background(Capsule().fill(Color(hex: Self.color)))
                    }
                    .buttonStyle(.plain)
                } else {
                    timerPrimary(running: timer.isRunning, color: Color(hex: Self.color), playPause)
                    timerCtl("arrow.counterclockwise", help: "Đặt lại") { timer.reset() }
                    TextField("Lời nhắc khi hết giờ…", text: $message)
                        .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.ink)
                        .focused($messageFocused)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(.ink.opacity(0.07)))
                        .disabled(inSession)
                        .opacity(inSession ? 0.4 : 1)
                        .onSubmit(playPause)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: timer.isRunning)
            presetRow
                .disabled(inSession)
                .opacity(inSession ? 0.35 : 1)
        }
        .onExitCommand { messageFocused = false }
    }

    private var subtitle: String {
        if timer.justFinished { return "Bấm OK để tắt" }
        if timer.isRunning {
            let end = Date().addingTimeInterval(timer.remaining)
            return "Kết thúc lúc \(end.formatted(date: .omitted, time: .shortened))"
        }
        if inSession { return "Đang tạm dừng" }
        return "\(minutes) phút · chọn nhanh bên dưới"
    }

    private var presetRow: some View {
        HStack(spacing: 5) {
            ForEach(Self.presets, id: \.self) { m in
                let on = m == minutes
                Button { withAnimation(.snappy(duration: 0.25)) { minutes = m } } label: {
                    Text("\(m)′").font(.system(size: 10, weight: on ? .bold : .medium)).monospacedDigit()
                        .foregroundStyle(on ? Color.inkInverse : .ink.opacity(0.75))
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(on ? .ink.opacity(0.9) : .ink.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(.ink.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 2)
            stepBtn("minus") { minutes = max(1, minutes - 1) }
            stepBtn("plus") { minutes = min(180, minutes + 1) }
        }
    }

    private func stepBtn(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { action() } } label: {
            Image(systemName: name).font(.system(size: 9, weight: .bold)).foregroundStyle(.ink.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func playPause() {
        if timer.isRunning { timer.pause() }
        else if inSession { timer.resume() }
        else { timer.startPlain(minutes: minutes, label: message); messageFocused = false }
    }
}

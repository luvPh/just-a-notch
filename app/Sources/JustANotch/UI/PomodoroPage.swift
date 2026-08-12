import SwiftUI

// Trang "Pomodoro" của carousel Timer: chu kỳ Làm/Nghỉ tự luân phiên + chỉnh cấu hình.
struct PomodoroPage: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    @State private var configuring = false

    private var phaseColor: Color {
        switch timer.phase {
        case .work:                   return Color(red: 0.96, green: 0.36, blue: 0.33)
        case .shortBreak, .longBreak: return Color(red: 0.30, green: 0.82, blue: 0.52)
        }
    }
    private var titleLine: String {
        switch timer.phase {
        case .work:       return "Làm việc"
        case .shortBreak: return "Nghỉ ngắn"
        case .longBreak:  return "Nghỉ dài"
        }
    }
    // Pomodoro dùng remaining khi đang chạy, ngược lại hiện độ dài pha hiện tại.
    private var seconds: Int {
        let base = timer.remaining > 0 ? timer.remaining : Double(settings.pomoWorkMinutes * 60)
        return max(0, Int(base.rounded()))
    }
    private var mm: String { String(format: "%02d", seconds / 60) }
    private var ss: String { String(format: "%02d", seconds % 60) }

    var body: some View {
        Group {
            if configuring { configView } else { clockView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var clockView: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                FlipDigit(char: mm.first!, accent: phaseColor)
                FlipDigit(char: mm.last!,  accent: phaseColor)
                Text(":")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55)).padding(.bottom, 3)
                FlipDigit(char: ss.first!, accent: phaseColor)
                FlipDigit(char: ss.last!,  accent: phaseColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleLine)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(phaseColor)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text("Vòng \(timer.completedWorkRounds + 1)/\(settings.pomoRounds)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45)).fixedSize()
                }
                .frame(width: 74, alignment: .leading)
                .padding(.leading, 4)
            }

            HStack(spacing: 7) {
                if timer.isRunning {
                    ctl("pause.fill", tint: phaseColor) { timer.pause() }
                } else {
                    ctl("play.fill", tint: phaseColor) {
                        if timer.remaining > 0 { timer.resume() } else { timer.startPomodoro() }
                    }
                }
                ctl("arrow.counterclockwise") { timer.reset() }
                ctl("forward.end.fill") { timer.skip() }
                Divider().frame(height: 16).overlay(.white.opacity(0.12))
                ctl("slider.horizontal.3") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { configuring = true }
                }
            }
        }
    }

    private var configView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                backButton { configuring = false }
                Text("Cấu hình Pomodoro").font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }
            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    stepRow("Làm", value: $settings.pomoWorkMinutes, range: 1...120, suffix: "m")
                    stepRow("Nghỉ ngắn", value: $settings.pomoShortMinutes, range: 1...60, suffix: "m")
                    stepRow("Nghỉ dài", value: $settings.pomoLongMinutes, range: 1...60, suffix: "m")
                    stepRow("Số vòng", value: $settings.pomoRounds, range: 1...12, suffix: "")
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Tự chạy pha kế").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Toggle("", isOn: $settings.pomoAutoStart).labelsHidden().toggleStyle(GlowToggleStyle())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: helpers

    private func ctl(_ name: String, tint: Color = .white, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint == .white ? .white.opacity(0.85) : Color.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint == .white ? .white.opacity(0.08) : tint))
        }
        .buttonStyle(.plain)
    }

    private func stepRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 9) {
            Text("\(label): \(value.wrappedValue)\(suffix)")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Stepper("", value: value, in: range).labelsHidden()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }
}

// Nút quay lại dùng chung cho các panel con của Timer.
func backButton(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.left")
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            .frame(width: 24, height: 24)
            .background(Circle().fill(.white.opacity(0.1)))
    }
    .buttonStyle(.plain)
}

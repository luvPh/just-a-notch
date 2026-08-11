import SwiftUI

struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    private var progress: Double {
        guard timer.phaseLength > 0 else { return 0 }
        return 1 - (timer.remaining / timer.phaseLength)
    }
    private var phaseColor: Color {
        switch timer.phase {
        case .work:                   return .red
        case .shortBreak, .longBreak: return .green
        }
    }
    private var mmss: String {
        let s = Int(timer.remaining.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    private var phaseLabel: String {
        switch timer.phase {
        case .work:       return "Làm việc"
        case .shortBreak: return "Nghỉ ngắn"
        case .longBreak:  return "Nghỉ dài"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text(mmss).font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            if timer.mode == .pomodoro {
                Text("Vòng \(timer.completedWorkRounds + 1)/\(settings.pomoRounds)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if timer.isRunning {
                    Button("Tạm dừng") { timer.pause() }
                } else {
                    Button("Bắt đầu") {
                        if timer.remaining > 0 { timer.resume() } else { timer.startPomodoro() }
                    }
                }
                Button("Đặt lại") { timer.reset() }
                Button("Bỏ qua") { timer.skip() }
            }
            .buttonStyle(.bordered).font(.caption)

            HStack(spacing: 6) {
                ForEach([5, 10, 25], id: \.self) { m in
                    Button("\(m)m") { timer.startPlain(minutes: m) }
                        .buttonStyle(.borderless).font(.caption2)
                }
            }
        }
        .padding(12)
    }
}

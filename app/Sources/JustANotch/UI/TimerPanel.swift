import SwiftUI

// Trang "Đơn" của carousel Timer: hẹn giờ một lần (đếm ngược) hoặc stopwatch
// (đếm lên). Không dính tới Pomodoro (trang riêng).
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    @State private var editing = false
    @State private var countUp = false
    @State private var customMinutes = 15
    @State private var customMessage = ""

    private let accent = Color(red: 0.64, green: 0.55, blue: 0.98)

    private var shownSeconds: Int {
        countUp ? Int(timer.elapsed.rounded()) : max(0, Int(timer.remaining.rounded()))
    }
    private var mm: String { String(format: "%02d", shownSeconds / 60) }
    private var ss: String { String(format: "%02d", shownSeconds % 60) }

    var body: some View {
        Group {
            if timer.justFinished {
                doneView
            } else if editing {
                editorView
            } else {
                clockView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Clock

    private var clockView: some View {
        VStack(spacing: 9) {
            modeToggle

            HStack(spacing: 5) {
                FlipDigit(char: mm.first!, accent: accent)
                FlipDigit(char: mm.last!,  accent: accent)
                Text(":")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55)).padding(.bottom, 3)
                FlipDigit(char: ss.first!, accent: accent)
                FlipDigit(char: ss.last!,  accent: accent)
            }

            HStack(spacing: 7) {
                if timer.isRunning {
                    ctl("pause.fill", tint: accent) { timer.pause() }
                } else {
                    ctl("play.fill", tint: accent) {
                        if countUp { timer.startStopwatch() }
                        else if timer.remaining > 0 { timer.resume() }
                        else { timer.startPlain(minutes: customMinutes) }
                    }
                }
                ctl("arrow.counterclockwise") { timer.reset() }

                if !countUp {
                    Divider().frame(height: 16).overlay(.white.opacity(0.12))
                    ForEach([5, 10, 25], id: \.self) { m in
                        Button { timer.startPlain(minutes: m) } label: {
                            Text("\(m)′")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 25, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    ctl("slider.horizontal.3") {
                        customMessage = ""
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editing = true }
                    }
                }
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            segButton("Đếm ngược", on: !countUp) { setCountUp(false) }
            segButton("Đếm lên", on: countUp) { setCountUp(true) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func segButton(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(on ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12).frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? .white.opacity(0.9) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func setCountUp(_ up: Bool) {
        guard up != countUp else { return }
        timer.reset()
        withAnimation(.easeOut(duration: 0.15)) { countUp = up }
    }

    // MARK: Editor (custom minutes + message)

    private var editorView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Phút").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                stepBtn("minus") { customMinutes = max(1, customMinutes - 1) }
                Text("\(customMinutes)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                    .frame(minWidth: 34)
                stepBtn("plus") { customMinutes = min(180, customMinutes + 1) }
                Spacer(minLength: 0)
                ForEach([5, 15, 30], id: \.self) { m in
                    Button { customMinutes = m } label: {
                        Text("\(m)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(customMinutes == m ? .black : .white.opacity(0.7))
                            .frame(width: 22, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(customMinutes == m ? .white.opacity(0.9) : .white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Lời nhắc khi hết giờ…", text: $customMessage)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editing = false }
                } label: {
                    Text("Huỷ").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button {
                    timer.startPlain(minutes: customMinutes, label: customMessage)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editing = false }
                } label: {
                    Text("Bắt đầu").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(red: 0.30, green: 0.82, blue: 0.52))
            Text(timer.label.isEmpty ? "Hết giờ!" : timer.label)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { timer.dismissFinished() } label: {
                Text("OK").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 22).frame(height: 26)
                    .background(Capsule().fill(.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Buttons

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

    private func stepBtn(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

// A single split-flap digit card with a center seam; the digit flips vertically
// when it changes. Dùng chung cho các trang timer.
struct FlipDigit: View {
    let char: Character
    let accent: Color

    var body: some View {
        Text(String(char))
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 30, height: 44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.10),
                                                      Color.white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                    Rectangle().fill(.black.opacity(0.55)).frame(height: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .id(char)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)))
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: char)
    }
}

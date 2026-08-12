import SwiftUI

// Trang "Đơn" của carousel Timer: hẹn giờ một lần (đếm ngược). Không dính tới
// Pomodoro (trang riêng).
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var locked: Bool

    @State private var editing = false
    @State private var customMinutes = 15
    @State private var customMessage = ""

    private let accent = Color(red: 0.64, green: 0.55, blue: 0.98)

    private var shownSeconds: Int { max(0, Int(timer.remaining.rounded())) }
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
        .onChange(of: editing) { _, v in locked = v }
    }

    // MARK: Clock

    // Đồng hồ nhỏ (trái) + điều khiển (phải), gọn trong khung.
    private var clockView: some View {
        HStack(alignment: .center, spacing: 14) {
            clockDigits
            HStack(spacing: 7) {
                if timer.isRunning {
                    ctl("pause.fill", tint: accent) { timer.pause() }
                } else {
                    ctl("play.fill", tint: accent) {
                        if timer.remaining > 0 { timer.resume() }
                        else { timer.startPlain(minutes: customMinutes) }
                    }
                }
                ctl("arrow.counterclockwise") { timer.reset() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var clockDigits: some View {
        HStack(spacing: 3) {
            FlipDigit(char: mm.first!, accent: accent, fontSize: 24, w: 24, h: 34)
            FlipDigit(char: mm.last!,  accent: accent, fontSize: 24, w: 24, h: 34)
            Text(":")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55)).padding(.bottom, 2)
            FlipDigit(char: ss.first!, accent: accent, fontSize: 24, w: 24, h: 34)
            FlipDigit(char: ss.last!,  accent: accent, fontSize: 24, w: 24, h: 34)
        }
        // Bấm vào đồng hồ (khi rảnh) để nhập phút tuỳ chỉnh.
        .contentShape(Rectangle())
        .onTapGesture {
            guard !timer.isRunning else { return }
            customMessage = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editing = true }
        }
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
    var fontSize: CGFloat = 30
    var w: CGFloat = 30
    var h: CGFloat = 44

    var body: some View {
        Text(String(char))
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: w, height: h)
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

import SwiftUI

// Flip-clock timer that fits inside the fixed 150px notch panel (≈90px usable
// height below the camera core). Three states share the panel:
//   • clock   — split-flap MM:SS + controls (running / idle)
//   • editor  — user sets a custom duration + reminder message
//   • done    — the custom timer finished; shows the message until dismissed
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    @State private var editing = false
    @State private var showingSettings = false
    @State private var customMinutes = 15
    @State private var customMessage = ""

    private var phaseColor: Color {
        switch timer.phase {
        case .work:                   return Color(red: 0.96, green: 0.36, blue: 0.33)
        case .shortBreak, .longBreak: return Color(red: 0.30, green: 0.82, blue: 0.52)
        }
    }
    // Custom label (plain timer) wins over the generic phase name.
    private var titleLine: String {
        if timer.mode == .plain, !timer.label.isEmpty { return timer.label }
        switch timer.phase {
        case .work:       return "Làm việc"
        case .shortBreak: return "Nghỉ ngắn"
        case .longBreak:  return "Nghỉ dài"
        }
    }
    private var totalSeconds: Int { max(0, Int(timer.remaining.rounded())) }
    private var mm: String { String(format: "%02d", totalSeconds / 60) }
    private var ss: String { String(format: "%02d", totalSeconds % 60) }

    var body: some View {
        Group {
            if timer.justFinished {
                doneView
            } else if showingSettings {
                settingsView
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
                    if timer.mode == .pomodoro {
                        Text("Vòng \(timer.completedWorkRounds + 1)/\(settings.pomoRounds)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45)).fixedSize()
                    }
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
                // Custom duration + message.
                ctl("slider.horizontal.3") {
                    customMessage = timer.label
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editing = true }
                }
                // Cấu hình Pomodoro + âm báo.
                ctl("gearshape.fill") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { showingSettings = true }
                }
            }
        }
    }

    // MARK: Editor

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
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(red: 0.96, green: 0.36, blue: 0.33)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Settings (Pomodoro + âm báo) — sống ngay trong tab Timer.

    private var settingsView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { showingSettings = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                Text("Cấu hình Timer")
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    stepRow("Làm", value: $settings.pomoWorkMinutes, range: 1...120, suffix: "m")
                    stepRow("Nghỉ ngắn", value: $settings.pomoShortMinutes, range: 1...60, suffix: "m")
                    stepRow("Nghỉ dài", value: $settings.pomoLongMinutes, range: 1...60, suffix: "m")
                    stepRow("Số vòng", value: $settings.pomoRounds, range: 1...12, suffix: "")
                    switchRow("Tự chạy pha kế tiếp", icon: "arrow.triangle.2.circlepath",
                              isOn: $settings.pomoAutoStart)
                    switchRow("Chuông báo", icon: "bell.badge", isOn: $settings.timerSoundEnabled)

                    HStack(spacing: 9) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Âm chuông").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        StyledSoundPicker(selection: $settings.timerSoundName)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(rowBG)

                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Slider(value: $settings.timerVolume, in: 0...1)
                        Button {
                            if let snd = NSSound(named: settings.timerSoundName) {
                                snd.volume = Float(settings.timerVolume); snd.play()
                            }
                        } label: {
                            Text("Nghe thử").font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(rowBG)
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var rowBG: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05))
    }

    private func stepRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 9) {
            Text("\(label): \(value.wrappedValue)\(suffix)")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Stepper("", value: value, in: range).labelsHidden()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(rowBG)
    }

    private func switchRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
            Text(label).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(GlowToggleStyle())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(rowBG)
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
// when it changes.
private struct FlipDigit: View {
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

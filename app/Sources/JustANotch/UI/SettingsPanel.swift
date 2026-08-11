import SwiftUI
import AppKit

/// The Settings tab body. Scrollable list of grouped preferences styled to
/// match the notch's dark, translucent aesthetic. Reads/writes AppSettings.
struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var vm: NotchViewModel

    private static let repoURL = URL(string: "https://github.com/luvPh/just-a-notch")!

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                // MARK: Chung
                section("Chung") {
                    toggleRow("Mở cùng lúc đăng nhập", icon: "power",
                              isOn: Binding(get: { settings.launchAtLogin },
                                            set: { settings.setLaunchAtLogin($0) }))
                }

                // MARK: Tabs
                section("Tabs") {
                    toggleRow("Files", icon: "folder.fill", isOn: $settings.showFiles)
                    toggleRow("Notifications", icon: "bell.fill", isOn: $settings.showNotifications)
                    toggleRow("Lịch", icon: "calendar", isOn: $settings.showCalendar)
                    toggleRow("Clipboard", icon: "doc.on.clipboard", isOn: $settings.showClipboard)
                    toggleRow("Timer", icon: "timer", isOn: $settings.showTimer)
                    Text("Now Playing và Settings luôn được bật.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }

                // MARK: Timer / Pomodoro
                section("Timer / Pomodoro") {
                    stepperRow("Làm", value: $settings.pomoWorkMinutes, range: 1...120, suffix: "m")
                    stepperRow("Nghỉ ngắn", value: $settings.pomoShortMinutes, range: 1...60, suffix: "m")
                    stepperRow("Nghỉ dài", value: $settings.pomoLongMinutes, range: 1...60, suffix: "m")
                    stepperRow("Số vòng trước nghỉ dài", value: $settings.pomoRounds, range: 1...12, suffix: "")
                    toggleRow("Tự chạy pha kế tiếp", icon: "arrow.triangle.2.circlepath", isOn: $settings.pomoAutoStart)
                    toggleRow("Chuông báo", icon: "bell.badge", isOn: $settings.timerSoundEnabled)

                    HStack(spacing: 9) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18)
                        Text("Âm chuông").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Picker("", selection: $settings.timerSoundName) {
                            ForEach(["Glass", "Ping", "Submarine", "Funk", "Blow"], id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))

                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18)
                        Text("Âm lượng").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Slider(value: $settings.timerVolume, in: 0...1)
                        Button("Nghe thử") {
                            if let snd = NSSound(named: settings.timerSoundName) {
                                snd.volume = Float(settings.timerVolume)
                                snd.play()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                }

                // MARK: Notifications
                section("Notifications") {
                    HStack(spacing: 8) {
                        statusDot(vm.notificationsPermissionDenied ? .red : .green)
                        Text(vm.notificationsPermissionDenied ? "Chưa cấp Full Disk Access" : "Đã cấp quyền")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))

                    linkButton("Mở Full Disk Access", icon: "arrow.up.forward.app") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                // MARK: Phím tắt
                section("Phím tắt") {
                    toggleRow("Nhấn nhanh ⌘ hai lần để bật/tắt notch",
                              icon: "command", isOn: $settings.doubleTapCommand)
                    Text("Cần cấp Accessibility lần đầu. Ngoài ra: ⌥N bật/tắt · ⌥Space play/pause · ⌥←/→ đổi bài · ⌥1/2/3 chọn tab.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }

                // MARK: Motion
                section("Motion") {
                    toggleRow("Giảm chuyển động", icon: "wind", isOn: $settings.forceReduceMotion)
                    Text("Tắt các hiệu ứng lò xo/trượt để notch phản hồi tức thì.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }

                // MARK: About
                section("About") {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Just a Notch").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            Text("Phiên bản \(appVersion)").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)

                    linkButton("Mã nguồn trên GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                        NSWorkspace.shared.open(Self.repoURL)
                    }
                    linkButton("Thoát ứng dụng", icon: "power", destructive: true) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 4)
            content()
        }
    }

    private func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18)
            Text(label).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(GlowToggleStyle())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 9) {
            Text("\(label): \(value.wrappedValue)\(suffix)")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func linkButton(_ label: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)
                Text(label).font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color(red: 0.98, green: 0.45, blue: 0.42) : .white.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(destructive ? 0.04 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.7), radius: 2)
    }
}

/// Compact switch: soft purple track + glow when ON, neutral grey when OFF.
private struct GlowToggleStyle: ToggleStyle {
    // A gentle lavender that reads as "purple" without being loud.
    private let purple = Color(red: 0.64, green: 0.55, blue: 0.98)

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? purple.opacity(0.9) : Color.white.opacity(0.14))
                    .overlay(
                        Capsule().stroke(purple.opacity(on ? 0.9 : 0), lineWidth: 0.5)
                    )
                    // Soft glow only when ON.
                    .shadow(color: purple.opacity(on ? 0.45 : 0), radius: 3)
                    .shadow(color: purple.opacity(on ? 0.25 : 0), radius: 6)
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            }
            .frame(width: 30, height: 18)
            .contentShape(Capsule())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
        }
        .buttonStyle(.plain)
    }
}

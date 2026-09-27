import SwiftUI
import AppKit

/// The Settings tab body. Scrollable list of grouped preferences styled to
/// match the notch's dark, translucent aesthetic. Reads/writes AppSettings.
struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var claude = ClaudeActivityStore.shared

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
                    toggleRow("Learn", icon: "graduationcap.fill", isOn: $settings.showLearn)
                    Text("Now Playing và Settings luôn được bật.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }

                // MARK: Learn
                section("Learn") {
                    toggleRow("Tự bung 1 từ định kỳ", icon: "sparkles", isOn: $settings.learnAutoPopup)
                    HStack(spacing: 9) {
                        Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Mỗi \(settings.learnPopupMinutes) phút").font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Stepper("", value: $settings.learnPopupMinutes, in: 5...180, step: 5).labelsHidden()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    HStack(spacing: 9) {
                        Image(systemName: settings.learnPaused ? "pause.circle.fill" : "pause.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text(settings.learnPauseLabel ?? "Tạm dừng popup").font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        if settings.learnPaused {
                            Button("Tiếp tục") { settings.learnPausedUntil = nil }
                                .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            Menu("Chọn") {
                                ForEach(AppSettings.learnPauseOptions(), id: \.0) { opt in
                                    Button(opt.0) { settings.learnPausedUntil = opt.1 }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    toggleRow("Bỏ qua khi app full màn hình", icon: "arrow.up.left.and.arrow.down.right", isOn: $settings.learnSkipFullscreen)
                    toggleRow("Âm báo khi bung", icon: "bell.and.waves.left.and.right", isOn: $settings.learnSoundEnabled)
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Âm lượng").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Slider(value: $settings.learnSoundVolume, in: 0...1)
                        Button("Nghe thử") { LearnChime.play(volume: Float(settings.learnSoundVolume)) }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    linkButton("Mở cửa sổ học", icon: "macwindow") { LearnWindowController.shared.show() }
                }

                // MARK: Claude Code
                section("Claude Code") {
                    toggleRow("Hiện tiến trình + báo xong/chờ duyệt", icon: "sparkle", isOn: $settings.claudeOn)
                    HStack(spacing: 9) {
                        Image(systemName: "bell.and.waves.left.and.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Âm báo").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Button("Xong") { ClaudeChime.play(.done) }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        Button("Chờ duyệt") { ClaudeChime.play(.waiting) }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        Toggle("", isOn: $settings.claudeSoundOn).labelsHidden().toggleStyle(GlowToggleStyle())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    HStack(spacing: 8) {
                        statusDot(claude.receivedAny ? .green : .orange)
                        Text(claude.receivedAny ? "Đã nhận sự kiện từ hook" : "Chưa nhận sự kiện hook nào")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    linkButton("Copy đường dẫn thư mục sự kiện", icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ClaudeActivityStore.eventsDir.path, forType: .string)
                    }
                    Text("Notch đọc sự kiện hook Claude Code (mỗi sự kiện một file .json trong thư mục trên). Cần đăng ký hook SessionStart · UserPromptSubmit · PreToolUse · Notification · Stop · SessionEnd ghi stdin vào đó.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }

                // MARK: Nhắc nghỉ
                section("Nhắc đứng dậy · uống nước") {
                    toggleRow("Nhắc mỗi 30 phút trong giờ làm", icon: "figure.stand", isOn: $settings.breakReminderOn)
                    toggleRow("Âm báo", icon: "drop.fill", isOn: $settings.breakSoundOn)
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Âm lượng").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Slider(value: $settings.breakVolume, in: 0...1)
                        Button("Nghe thử") { BreakChime.play(volume: Float(settings.breakVolume)) }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    linkButton("Xem thử lời nhắc", icon: "eye") {
                        vm.collapse()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { vm.showBreak() }
                    }
                    Text("T2–T6, 9:30–11:30 và 13:30–17:30 (bỏ giờ trưa, ngày lễ). Rời máy quá 5 phút thì bỏ lượt; app full màn hình thì không kêu.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
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

                    toggleRow("Âm báo thông báo", icon: "bell.badge", isOn: $settings.notifSoundEnabled)

                    HStack(spacing: 9) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18)
                        Text("Âm báo").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        StyledSoundPicker(selection: $settings.notifSoundName)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))

                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18)
                        Text("Âm lượng").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Slider(value: $settings.notifVolume, in: 0...1)
                        Button("Nghe thử") {
                            SoundLibrary.shared.play(settings.notifSoundName, volume: Float(settings.notifVolume))
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

                // MARK: Phím tắt
                section("Phím tắt") {
                    toggleRow("Nhấn nhanh ⌘ hai lần để bật/tắt notch",
                              icon: "command", isOn: $settings.doubleTapCommand)
                    toggleRow("F1–F6 mở app ở mọi nơi",
                              icon: "f.square", isOn: $settings.fKeyAppsEnabled)
                    if settings.fKeyAppsEnabled {
                        ForEach(0..<AppSettings.fKeyCount, id: \.self) { i in fKeyRow(i) }
                    }
                    Text("F1–F6 (bàn phím Apple: fn+F1–F6) đưa app đã gán ra trước — đang chạy thì giữ nguyên cửa sổ, chưa chạy thì mở mới. Khi bật, 6 phím này thuộc về app nên chức năng gốc của chúng (độ sáng, Mission Control…) tạm nghỉ.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
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

    /// Một ô gán app cho F(i+1): icon app, tên, nút chọn / bỏ gán.
    private func fKeyRow(_ i: Int) -> some View {
        let slot = settings.fKeyApps.indices.contains(i) ? settings.fKeyApps[i] : nil
        let appURL = slot.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID)
        }
        return HStack(spacing: 9) {
            Text("F\(i + 1)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.09)))
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().interpolation(.high).frame(width: 15, height: 15)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 15)
            }
            Text(slot?.name ?? "Chưa gán")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(slot == nil ? 0.4 : 0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(slot == nil ? "Chọn app…" : "Đổi") { pickApp(for: i) }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.1)))
            if slot != nil {
                Button {
                    settings.fKeyApps[i] = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    /// Chọn app bằng NSOpenPanel (lọc đúng bundle .app), lưu bundle id + tên.
    private func pickApp(for i: Int) {
        let panel = NSOpenPanel()
        panel.title = "Chọn app cho F\(i + 1)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // Panel cần app active để nhận bàn phím/chuột như một cửa sổ thường.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        settings.fKeyApps[i] = FKeyApp(bundleID: id, name: name)
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

/// A dropdown styled to match the notch (dark chip + custom chevron) instead of
/// the stock blue macOS Picker. Menu-based so we control the whole label.
struct StyledSoundPicker: View {
    @Binding var selection: String
    /// Mặc định lấy toàn bộ âm từ SoundLibrary (hệ thống + bundle). Có thể truyền
    /// danh sách riêng nếu cần.
    var options: [String] = SoundLibrary.shared.names

    @State private var hovering = false
    private let purple = Color(red: 0.64, green: 0.55, blue: 0.98)

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { name in
                Button {
                    selection = name
                    // Nghe ngay khi chọn để dễ so sánh.
                    SoundLibrary.shared.play(name)
                } label: {
                    if selection == name { Label(name, systemImage: "checkmark") }
                    else { Text(name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.9))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.5))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(hovering ? 0.18 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(purple.opacity(hovering ? 0.7 : 0), lineWidth: 1))
            .shadow(color: purple.opacity(hovering ? 0.3 : 0), radius: 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Compact switch: soft purple track + glow when ON, neutral grey when OFF.
struct GlowToggleStyle: ToggleStyle {
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

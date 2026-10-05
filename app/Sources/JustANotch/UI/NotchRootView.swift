import SwiftUI

private let alcoveRed = Color(red: 0.96, green: 0.36, blue: 0.33)

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    // Observe cả ba đồng hồ để wing/badge refresh theo tick của bất kỳ cái nào
    // (nested ObservableObjects không tự republish `vm`).
    @ObservedObject private var timerSingle: TimerService
    @ObservedObject private var timerPomodoro: TimerService
    @ObservedObject private var timerSequence: TimerService
    @ObservedObject private var settings = AppSettings.shared

    // Đồng hồ để hiển thị ở wing (ưu tiên cái đang chạy).
    private var timer: TimerService { vm.displayTimer }

    init(vm: NotchViewModel, initialTab: RailTab = .music) {
        _vm = ObservedObject(wrappedValue: vm)
        _railTab = State(initialValue: initialTab)
        _timerSingle = ObservedObject(wrappedValue: vm.timerSingle)
        _timerPomodoro = ObservedObject(wrappedValue: vm.timerPomodoro)
        _timerSequence = ObservedObject(wrappedValue: vm.timerSequence)
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var railTab: RailTab = .music
    // Nút ⚙️ ở wing phải notch (tab Timer) mở panel cài đặt tổng.
    @State private var timerSettingsOpen = false

    // System setting OR the user's manual override in Settings → Motion.
    private var reduceMotion: Bool { systemReduceMotion || settings.forceReduceMotion }

    // Music + Settings are always present; the middle tabs follow user toggles.
    private var visibleTabs: [RailTab] {
        var t: [RailTab] = [.music]
        if settings.showNotifications { t.append(.notifications) }
        if settings.showCalendar { t.append(.calendar) }
        if settings.showClipboard { t.append(.clipboard) }
        if settings.showTimer { t.append(.timer) }
        if settings.showLearn { t.append(.learn) }
        t.append(.settings)
        return t
    }
    @State private var calMode: CalMode = .solar
    @State private var calAnchor: Date = Date()
    // While the user is dragging the scrubber, show their position instead of the
    // (2s-polled) real progress; hold it briefly after release so it doesn't snap
    // back before the next poll catches up.
    @State private var scrubFraction: Double?
    @State private var scrubHold: DispatchWorkItem?
    @State private var volFraction: Double?
    @State private var volHold: DispatchWorkItem?
    @State private var showVolume = false
    @State private var volumeAutoHide: DispatchWorkItem?
    @State private var lastSentVolume: Double = -1
    @State private var artHover = false
    @State private var waveHover = false
    @State private var hoveredQueueID: String?
    // Notifications: which app-piles are expanded (by bundleId).
    @State private var expandedGroups: Set<String> = []
    // Local keyDown monitor active while the panel is expanded (installed on appear).
    @State private var keyMonitor: Any?

    private var openSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.8)
    }
    /// Thu vào: lò xo KHÔNG nảy (damping 1) — tránh notch co lố nhỏ hơn camera rồi bật lại.
    private var closeSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 1)
    }
    private var revealSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)
    }
    // Smooth, barely-settling spring for the hover wing-expand + waveform morph.
    private var hoverSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.78)
    }

    var body: some View {
        VStack(spacing: 0) {
            surface
                // Everything animates INSIDE the fixed panel, top-anchored — the surface
                // grows straight down from the notch (prototype behaviour).
                .frame(width: vm.surfaceWidth, height: vm.surfaceHeight, alignment: .top)
                // A whisper of lift on hover; the real reveal is the wing widening
                // to expose the transport controls (see `compactRight`).
                // Launcher mở ra từ trạng thái hover → giữ nguyên mức phóng để notch không
                // co lại lúc dải icon thả xuống; đóng launcher mới trở về 1.0.
                .scaleEffect(vm.hoverScale * vm.pillScale, anchor: .top)
                // Chuyển màn: co về giữa-trên rồi mờ đi; ở màn mới phóng từ nhỏ lên (không blur:
                // blur làm viền loang to hơn kích thước thật → trông như "to rồi co lại").
                // Pill: co đều về tâm. Notch: thu NGANG vào camera (giữ chiều cao, neo mép trên).
                .scaleEffect(x: vm.screenHopHidden ? (vm.pillMode ? 0.4 : 0.12) : 1,
                             y: vm.screenHopHidden ? (vm.pillMode ? 0.4 : 1) : 1,
                             anchor: vm.pillMode ? .center : .top)
                .opacity(vm.screenHopHidden ? 0 : 1)
                .offset(x: vm.centerXOffset, y: vm.pillMode ? vm.pillGap : 0)
                .onHover { vm.hovering = vm.screenHopHidden ? false : $0 }
                .animation(vm.hovering ? hoverSpring : closeSpring, value: vm.hovering)   // rời chuột: co về 1.0 không lố
                // Mở ra được nảy nhẹ; THU VÀO luôn dùng closeSpring (không co lố).
                .animation(vm.compactState == .reading ? revealSpring : closeSpring, value: vm.compactState)
                .animation(vm.expanded ? openSpring : closeSpring, value: vm.expanded)
                .animation(vm.shelfActive ? openSpring : closeSpring, value: vm.shelfActive)
                .animation(vm.showList ? openSpring : closeSpring, value: vm.showList)
                // Notch phình ra/thu lại mềm khi mở tab cao hơn (Lịch).
                .animation(vm.panelWantsTall ? openSpring : closeSpring, value: vm.panelWantsTall)
                // Đổi kích thước (tab, dải phình…): không nảy để không bao giờ co lố.
                .animation(closeSpring, value: vm.surfaceHeight)
                // Files mở rộng cả chiều ngang (ẩn sidebar) — phình mềm sang hai bên.
                .animation(closeSpring, value: vm.surfaceWidth)
                .animation(vm.showingHUD ? revealSpring : closeSpring, value: vm.showingHUD)
                .animation(vm.launcherOpen ? openSpring : closeSpring, value: vm.launcherOpen)
                .animation(vm.launcherFeature != nil ? openSpring : closeSpring, value: vm.launcherFeature)
                .animation(vm.breakActive ? revealSpring : closeSpring, value: vm.breakActive)
                .animation(vm.claudeAlert != nil ? revealSpring : closeSpring, value: vm.claudeAlert)
                .animation(vm.claudeIndicatorVisible ? revealSpring : closeSpring, value: vm.claudeIndicatorVisible)
                .animation(closeSpring, value: vm.claudeBadges.count)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
        // Global hotkey ⌃⌥1/2/3 → nhảy tới tab thứ N trong danh sách đang hiển thị.
        // Mọi thao tác trong Lịch / Files đều hoãn đồng hồ tự thu 30s.
        .onChange(of: calAnchor) { _, _ in vm.noteInteraction() }
        .onChange(of: calMode) { _, _ in vm.noteInteraction() }
        .onChange(of: vm.calendarRows) { _, _ in vm.noteInteraction() }
        .onChange(of: vm.pendingTab) { _, tab in
            guard let tab else { return }
            if visibleTabs.contains(tab) { selectTab(tab) }
            vm.pendingTab = nil
        }
        .onChange(of: vm.pendingTabIndex) { _, idx in
            guard let idx else { return }
            if idx >= 1, idx <= visibleTabs.count { selectTab(visibleTabs[idx - 1]) }
            vm.pendingTabIndex = nil
        }
    }

    // MARK: Keyboard shortcuts (active only while the panel is expanded)
    //
    // The controller makes the (non-activating) panel key on expand, so keyDown
    // events route here. We consume the ones we handle (return nil) and pass the
    // rest through — including everything while a text field is being edited.

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKey(event) ? nil : event
        }
    }

    /// Returns true if the event was handled (and should be swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        // Launcher đang mở một tính năng (panel key) → Esc quay về hàng icon.
        if !vm.expanded, vm.launcherFeature != nil, event.keyCode == 53,
           !(NSApp.keyWindow?.firstResponder is NSText) {
            vm.launcherBack()
            return true
        }
        guard vm.expanded else { return false }
        // Never steal keys while editing a text field (rename / new catalogue).
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        // Leave app-level combos (⌘Q, ⌘W, …) alone — only bare keys are shortcuts.
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty else { return false }

        switch event.keyCode {
        case 53:                                    // Esc → collapse
            withAnimation(closeSpring) { vm.collapse() }
            return true
        case 49:                                    // Space → play/pause
            vm.playPause()
            return true
        case 123:                                   // ← : prev track / prev month
            return handleLeftRight(forward: false)
        case 124:                                   // → : next track / next month
            return handleLeftRight(forward: true)
        default:
            break
        }

        // Digits 1…N → jump to the Nth visible tab.
        if let ch = event.charactersIgnoringModifiers, let n = Int(ch), n >= 1, n <= visibleTabs.count {
            selectTab(visibleTabs[n - 1])
            return true
        }
        return false
    }


    private func handleLeftRight(forward: Bool) -> Bool {
        switch railTab {
        case .music:
            forward ? vm.next() : vm.previous()
            return true
        case .calendar:
            let delta = forward ? 1 : -1
            if let d = Calendar.current.date(byAdding: .month, value: delta, to: calAnchor) {
                withAnimation(openSpring) { calAnchor = d }
            }
            return true
        default:
            return false
        }
    }

    /// Switch tabs from the keyboard, mirroring the ThemeCarousel's onChange side
    /// effects so panel height / active-tab flags stay in sync.
    private func selectTab(_ tab: RailTab) {
        guard tab != railTab else { return }
        withAnimation(openSpring) { railTab = tab }
        vm.panelWantsTall = (tab == .calendar || tab == .settings || (tab == .learn && learnHasContent))
        vm.clipTabActive = (tab == .clipboard); vm.timerTabActive = (tab == .timer); vm.musicTabActive = (tab == .music)
        vm.calTabActive = (tab == .calendar)
        vm.notifTabActive = (tab == .notifications)
        if vm.showList { withAnimation(closeSpring) { vm.showList = false } }
        vm.noteInteraction()
    }

    private var surface: some View {
        let shape = NotchShape(bottom: vm.bottomRadius, inverse: vm.topRadius, top: vm.pillTopRadius)
        return ZStack(alignment: .top) {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.5), radius: vm.expanded ? 26 : 10, y: vm.expanded ? 14 : 5)

            // Ambient light cho thông báo: quầng màu toả từ đáy + một vệt sáng quét ngang.
            if let amb = notificationAmbient {
                AmbientSweep(tint: amb.tint, key: amb.key, reduceMotion: reduceMotion)
                    .transition(.opacity)
            }

            if vm.showingHUD {
                hudBanner.transition(.blurFade)
            } else if vm.shelfActive {
                ShelfPanel(store: vm.shelf,
                           onClose: { withAnimation(closeSpring) { vm.dismissShelf() } })
                    .transition(.blurFade)
            } else if vm.expanded && vm.learnPopup {
                LearnPopupCard(store: vm.learn, onDone: { withAnimation(closeSpring) { vm.finishLearnPopup() } },
                               keyboardReady: vm.learnPopupWantsKey)
                    .padding(.top, vm.notchHeight + 6)
                    .padding(.horizontal, 22).padding(.bottom, 14)
                    .transition(.blurFade)
            } else if vm.expanded {
                // Ambient light: mỗi tab một bộ màu toả nhẹ từ góc trái, gọn trong notch.
                // Tab nhạc lấy màu từ ảnh bìa.
                let amb = ambient(for: railTab)
                RadialGradient(stops: [.init(color: amb.secondary.opacity(amb.strength), location: 0),
                                       .init(color: amb.primary.opacity(amb.strength * 0.6), location: 0.4),
                                       .init(color: .clear, location: 0.78)],
                               center: amb.center, startRadius: 0, endRadius: 440)
                    .animation(.easeInOut(duration: 0.6), value: railTab)
                    .animation(.easeInOut(duration: 0.8), value: musicTint)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                player.transition(.blurFade)
            } else if vm.hasCompactContent || vm.launcherVisible || vm.bulge != nil {
                // Launcher: bề mặt canh giữa notch, hàng wing bù lệch tâm để lõi camera
                // vẫn nằm giữa; dải icon / tính năng thả xuống ngay dưới.
                VStack(spacing: 0) {
                    if vm.hasCompactContent {
                        compact.offset(x: vm.launcherVisible ? vm.wingImbalance : 0)
                    } else {
                        Color.clear.frame(height: vm.compactHeight)
                    }
                    // Thông báo phình xuống dưới notch (không nới rộng wing).
                    if let b = vm.bulge {
                        bulgeContent(b)
                            .frame(maxWidth: .infinity)
                            .frame(height: vm.bulgeHeight)
                            .padding(.bottom, 2)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                    removal: .opacity))
                    }
                    if vm.launcherVisible {
                        LauncherBody(vm: vm, reduceMotion: reduceMotion)
                            .frame(height: vm.launcherBodyHeight)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)),
                                                    removal: .opacity))
                    }
                }
                .transition(.blurFade)
            }
        }
        .clipShape(shape)
        // Viền notch nhấp nháy chậm khi đóng + đang giữ file (mời hover mở shelf).
        // Đặt SAU clipShape để glow/nửa ngoài của nét không bị cắt.
        .overlay {
            if vm.shelfGlowing {
                NotchEdgePulse(bottom: vm.bottomRadius, inverse: vm.topRadius, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contentShape(shape)
        .onTapGesture {
            if vm.showingHUD { vm.openSourceApp(); return }
            if vm.breakActive { vm.dismissBreak(); return }
            if vm.claudeAlert != nil { vm.openClaudeAlert(); return }
            // Đang trong một tính năng của launcher: bấm vùng trống không mở panel.
            if vm.launcherVisible && vm.launcherFeature != nil { return }
            if vm.shelfActive { vm.dismissShelf() }
            if !vm.expanded { vm.refreshMedia(); withAnimation(openSpring) { vm.expanded = true } }
        }
        // Chỉ thu notch khi bấm vùng header 220×40px ở giữa trên (trên lõi camera).
        // Hai wing hai bên để trống cho các nút chức năng, không lỡ tay thu app.
        .overlay(alignment: .top) {
            if vm.expanded {
                Color.clear
                    .frame(width: 220, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(closeSpring) { vm.collapse() } }
            }
        }
        // Không có media → không có compact wing/waveform, nên hiện badge đếm ngược
        // ngay ở wing phải. Có media thì badge nằm trong `compactRight` (thay chỗ
        // waveform) để không đè lên nhau.
        .overlay(alignment: .topTrailing) {
            if !vm.expanded, timer.isRunning, !vm.hasMedia {
                countdownBadge
                    .padding(.trailing, 12).padding(.top, 12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    /// Màu + khoá (đổi khoá = quét lại) của ambient light theo loại thông báo đang hiện.
    private var notificationAmbient: (tint: Color, key: String)? {
        if vm.showingHUD, let n = vm.hudNotification {
            return (Color(red: 0.35, green: 0.62, blue: 1.0), "hud-\(n.id)")
        }
        if vm.expanded && vm.learnPopup {
            return (Color(red: 0.30, green: 0.85, blue: 0.62), "learn")
        }
        switch vm.bulge {
        case .track:         return (musicTint.secondary, "track-\(vm.track?.title ?? "")")
        case .breakReminder: return (Color(red: 0.42, green: 0.78, blue: 1.0), "break")
        case .claude:        return (Color(red: 0.93, green: 0.52, blue: 0.38), "claude")
        case nil:            return nil
        }
    }

    /// Nội dung dải phình: nhắc nghỉ · Claude · đổi bài.
    @ViewBuilder private func bulgeContent(_ b: NotchViewModel.Bulge) -> some View {
        switch b {
        case .breakReminder:
            HStack(spacing: 10) {
                PixelCatSprite(reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Đứng dậy nào").font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 3) {
                        Text("uống ngụm nước").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                        Image(systemName: "drop.fill").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.42, green: 0.78, blue: 1.0))
                    }
                }
                .lineLimit(1).fixedSize()
            }
        case .claude:
            if let alert = vm.claudeAlert {
                ClaudeAlertView(vm: vm, alert: alert, reduceMotion: reduceMotion, centered: true)
            }
        case .track:
            if let t = vm.track {
                VStack(spacing: 1) {
                    MarqueeText(text: t.title, viewport: vm.surfaceWidth - 40,
                                onPanDuration: vm.scheduleTitleRetraction, centerIfFits: true)
                        .edgeFade(.horizontal, 10)
                    Text([t.artist, t.sourceAppName].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // Small countdown ring + remaining-minutes number, shared by the no-media
    // overlay and the compact right wing.
    private var countdownBadge: some View {
        ZStack {
            Circle().trim(from: 0, to: max(0.001, 1 - (timer.remaining / max(1, timer.phaseLength))))
                .stroke(timer.phase == .work ? Color(red: 0.96, green: 0.36, blue: 0.33)
                                             : Color(red: 0.30, green: 0.82, blue: 0.52),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 15, height: 15)
            Text("\(max(0, Int(timer.remaining / 60)))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: Compact (content in the wings; camera core stays empty)

    private var compact: some View {
        HStack(spacing: 0) {
            // ZStack có sẵn Color.clear: không có nhạc thì HStack bên trong rỗng, SwiftUI
            // bỏ luôn cả khung + overlay (Clawd) nếu không có gì làm nền.
            ZStack(alignment: .leading) {
            Color.clear
            HStack(spacing: 8) {
                if vm.claudeIndicatorVisible {
                    // Agent đang chạy/chờ duyệt → hình của nó thay chỗ icon nguồn nhạc; Claude +
                    // Codex cùng chạy thì đứng cạnh nhau. Bấm hình nào nhảy tới phiên đó.
                    // Thụt vào để né "tai" cong ở mép trái NotchShape.
                    HStack(spacing: 6) {
                        ForEach(vm.claudeBadges) { b in
                            ClaudeWingIndicator(waiting: b.waiting, sessionID: b.session.id,
                                                agent: b.agent, reduceMotion: reduceMotion)
                                .overlay(alignment: .bottomTrailing) {
                                    if b.count > 1 {
                                        Text("\(b.count)")
                                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.black)
                                            .frame(minWidth: 10, minHeight: 10)
                                            .background(Circle().fill(.white.opacity(0.9)))
                                            .offset(x: 3, y: 2)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { ClaudeActivityStore.focus(b.session) }
                                .transition(.blurFade)
                        }
                    }
                    // Notch: thụt vào né "tai" cong. Pill không có tai → sát trái như icon nhạc.
                    .padding(.leading, vm.pillMode ? 2 : 10)
                    .transition(.blurFade)
                } else if vm.hasMedia {
                    SourceIconButton(sourceApp: vm.track?.sourceAppName ?? "", reduceMotion: reduceMotion) {
                        vm.openSourceMediaApp()
                    }
                    .padding(.trailing, -6)   // khung bấm 30pt nhưng giữ khoảng cách tới tiêu đề như cũ
                    .offset(x: vm.pillMode ? -1 : 0, y: vm.pillMode ? -1 : 0)   // canh quang học trong pill
                    .transition(.blurFade)
                }
            }
            .padding(.leading, vm.pillMode ? 4 : 7)
            }
            .frame(width: vm.leftReveal, alignment: .leading)
            .clipped()

            Color.clear.frame(width: vm.coreWidth)
                .overlay {
                    // Pill: cảnh Clawd chill theo giờ ở giữa (notch thật thì chỗ này là camera).
                    if vm.pillMode && settings.pillMascot {
                        ChillSceneView(reduceMotion: reduceMotion)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }

            Group {
                if vm.hasMedia { compactRight.padding(.trailing, vm.pillMode ? 11 : 15) } else { Color.clear }
            }
                .frame(width: vm.rightReveal, alignment: .trailing)
                .frame(maxHeight: .infinity)
                // Cả wing phải là vùng bấm soundwave → hiện ◀ ⏯ ▶ (các nút con nhận bấm riêng).
                .contentShape(Rectangle())
                .onTapGesture { vm.showTransport() }
                .onHover { h in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { waveHover = h }
                }
                .clipped()
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
    }

    // Right wing: bấm soundwave → morph thành ◀ ⏯ ▶ transport controls.
    // Both layers share the trailing edge and cross-dissolve (opacity + blur +
    // scale) so the waveform appears to *become* the play/pause button while the
    // skip buttons unfold outward from it.
    private var compactRight: some View {
        let on = vm.hoverControls
        // While a timer runs (and the user isn't hovering controls), the countdown
        // badge takes the waveform's slot so the two never overlap.
        let showTimer = timer.isRunning && !on
        return ZStack(alignment: .trailing) {
            OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion, bars: 6)
                .frame(width: 18, height: 11)
                // Hover gợi ý "bấm được": sáng + phóng nhẹ.
                .brightness(waveHover && !on ? 0.25 : 0)
                .scaleEffect(waveHover && !on ? 1.18 : 1, anchor: .trailing)
                .opacity(on || timer.isRunning ? 0 : 1)
                .blur(radius: on || timer.isRunning ? 5 : 0)
                .scaleEffect(on ? 0.55 : 1, anchor: .trailing)

            countdownBadge
                .opacity(showTimer ? 1 : 0)
                .blur(radius: showTimer ? 0 : 5)
                .scaleEffect(showTimer ? 1 : 0.6, anchor: .trailing)
                .allowsHitTesting(false)

            HStack(spacing: 4) {
                compactCtl("backward.fill", 11) { vm.previous() }
                compactCtl(vm.isPlaying ? "pause.fill" : "play.fill", 14) { vm.playPause() }
                    .contentTransition(.symbolEffect(.replace))
                compactCtl("forward.fill", 11) { vm.next() }
            }
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : 5)
            .scaleEffect(on ? 1 : 0.62, anchor: .trailing)
            .allowsHitTesting(on)
        }
        .frame(maxHeight: .infinity, alignment: .trailing)
    }

    // Compact transport button with hover highlight + press feedback.
    private func compactCtl(_ name: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        CompactCtlButton(name: name, size: size, action: action)
    }

    // MARK: HUD banner (transient notification pop)

    private var hudBanner: some View {
        HStack(spacing: 11) {
            if let n = vm.hudNotification {
                Image(nsImage: vm.notificationIcon(n.bundleId))
                    .resizable().interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title.isEmpty ? n.appName : n.title)
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    if !n.detailLine.isEmpty {
                        Text(n.detailLine)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, vm.pillMode ? 0 : vm.notchHeight + 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(width: vm.hudWidth, height: vm.hudHeight, alignment: .leading)
    }

    // MARK: Expanded Alcove player

    private var player: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hàng header nằm NGANG camera: dải tab bên trái lõi, tên tab + công cụ bên phải.
            // Notch: vòng quay bên trái lõi camera. Pill: không có camera → vòng quay canh giữa.
            ZStack {
                HStack(spacing: 0) {
                    if !vm.pillMode {
                        TabWheel(tabs: visibleTabs, selection: $railTab, reduceMotion: reduceMotion)
                            .frame(width: headerSideWidth, height: vm.notchHeight)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Text(railTab.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .id(railTab).transition(.opacity)
                    }
                }
                if vm.pillMode {
                    TabWheel(tabs: visibleTabs, selection: $railTab, reduceMotion: reduceMotion)
                        .frame(width: 150, height: vm.notchHeight)
                }
            }
            .padding(.top, vm.pillMode ? 6 : 0)
            .frame(height: vm.notchHeight)
            .onChange(of: railTab) { _, newTab in
                vm.panelWantsTall = (newTab == .calendar || newTab == .settings || (newTab == .learn && learnHasContent))
                vm.clipTabActive = (newTab == .clipboard); vm.timerTabActive = (newTab == .timer); vm.musicTabActive = (newTab == .music)
                vm.calTabActive = (newTab == .calendar)
                vm.notifTabActive = (newTab == .notifications)
                // Rời music → thu queue để notch co về chiều cao mặc định.
                if vm.showList { withAnimation(closeSpring) { vm.showList = false } }
            }

            // Player controls stay fixed at the top; only the queue list scrolls
            // (the list has its own ScrollView). Fill the fixed window height so
            // that inner ScrollView gets a bounded height to scroll within.
            content
                .id(railTab)                 // re-run the transition on tab change
                .transition(.opacity)        // mờ nhanh, không blur/scale → không "gắt"
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxHeight: .infinity, alignment: .top)
                // Mờ dần 8pt cuối thay vì cắt cụt khi nội dung chạm đáy. Mask NỚI RỘNG 24pt
                // sang trái/phải/trên: hover phóng to, bóng đổ, glow không bị gọt mép
                // (notch tự clip theo hình dạng của nó ở ngoài cùng).
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 8)
                    }
                    .padding(.horizontal, -24).padding(.top, -24)
                )
                .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.82),
                           value: railTab)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Learn chỉ cần notch cao khi đang có thẻ học / màn hoàn thành; trống thì giữ thấp.
    private var learnHasContent: Bool { vm.learn.current != nil || vm.learn.dailyComplete }

    /// Bề ngang mỗi bên header (trái/phải lõi camera). Pill: không có camera → dùng nửa bề mặt.
    private var headerSideWidth: CGFloat {
        let core = vm.pillMode ? 0 : vm.coreWidth + 12
        return min(150, max(60, (vm.surfaceWidth - core) / 2 - 22))
    }

    // The right-hand panel — swaps with the centered carousel tab.
    @ViewBuilder private var content: some View {
        switch railTab {
        case .music:         musicPanel
        case .notifications: notificationsPanel
        case .calendar:      calendarPanel
        case .clipboard:     ClipboardPanel(store: vm.clipboard)
        case .learn:         LearnPanel(store: vm.learn)
        case .timer:         TimerCarousel(single: vm.timerSingle, pomodoro: vm.timerPomodoro,
                                           sequence: vm.timerSequence, settings: AppSettings.shared,
                                           showingSettings: $timerSettingsOpen, tall: $vm.timerEditorTall)
        case .settings:      DeferredMount { SettingsPanel(settings: settings, vm: vm) }
        default:             placeholderPanel(railTab)
        }
    }

    private var calendarPanel: some View {
        CalendarPanel(mode: $calMode, anchor: $calAnchor,
                      expanded: Binding(get: { vm.calExpanded },
                                        set: { vm.calExpanded = $0 }),
                      onRowsChange: { vm.calendarRows = $0 })
    }


    static func clock(_ t: Double) -> String {
        let s = max(0, Int(t.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    private struct Ambient {
        var primary: Color, secondary: Color, strength: Double, center: UnitPoint
    }

    /// Bộ màu ambient cho từng tab.
    private func ambient(for tab: RailTab) -> Ambient {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        let corner = UnitPoint(x: 0.08, y: 0.35)
        switch tab {
        case .music:
            return .init(primary: musicTint.primary, secondary: musicTint.secondary, strength: 0.30,
                         center: UnitPoint(x: 0.12, y: 0.72))
        case .notifications: return .init(primary: c(0.30, 0.55, 1.00), secondary: c(0.35, 0.85, 0.95), strength: 0.22, center: corner)
        case .calendar:      return .init(primary: NotchTheme.accent,  secondary: c(1.00, 0.72, 0.40), strength: 0.22, center: corner)
        case .clipboard:     return .init(primary: c(0.55, 0.45, 1.00), secondary: c(0.92, 0.50, 0.85), strength: 0.20, center: corner)
        case .timer:         return .init(primary: NotchTheme.accent,  secondary: c(1.00, 0.55, 0.30), strength: 0.24, center: corner)
        case .learn:         return .init(primary: c(0.30, 0.75, 0.55), secondary: c(0.30, 0.70, 0.95), strength: 0.22, center: corner)
        case .settings:      return .init(primary: c(0.55, 0.60, 0.72), secondary: c(0.70, 0.74, 0.85), strength: 0.14, center: corner)
        }
    }

    private var musicTint: ArtworkPalette.Tint {
        ArtworkPalette.tint(for: vm.track?.artworkData)
            // Không có ảnh bìa → khớp màu ảnh bìa mặc định (gradient xanh–tím của `Artwork`).
            ?? .init(primary: Color(red: 0.42, green: 0.55, blue: 0.98), secondary: Color(red: 0.78, green: 0.42, blue: 0.92))
    }

    private var musicPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                musicArtwork
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.track?.title ?? "Chưa phát gì")
                                .font(.system(size: 17, weight: .bold)).tracking(-0.2)
                                .foregroundStyle(.white).lineLimit(1)
                            Text([vm.track?.artist, vm.track?.sourceAppName].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12.5)).foregroundStyle(NotchTheme.secondaryText).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion,
                                        tint: musicTint.secondary, bars: 6)
                            .frame(width: 20, height: 14)
                    }
                    VStack(spacing: 3) {
                        scrubber.frame(height: 12)
                        if let d = vm.track?.duration {
                            let p = scrubFraction ?? vm.track?.progress ?? 0
                            HStack {
                                Text(Self.clock(p * d))
                                Spacer()
                                Text("-" + Self.clock((1 - p) * d))
                            }
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    musicTransport.frame(height: 38)
                }
            }
            .padding(.top, 3)   // cả cụm ảnh bìa + thông tin dịch xuống 3px

            if vm.showList {
                queueList.transition(.blurFade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Ảnh bìa lớn: quầng sáng màu ảnh bìa toả phía sau, bóng đổ, hover → nút mở app nguồn.
    private var musicArtwork: some View {
        let side: CGFloat = 116, r: CGFloat = 14
        return Button { vm.openSourceMediaApp() } label: {
            Artwork(data: vm.track?.artworkData, corner: r)
                .frame(width: side, height: side)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                }
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: r, style: .continuous).fill(.black.opacity(artHover ? 0.35 : 0))
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(artHover ? 0.95 : 0))
                    }
                }
                // Bóng đổ gọn, sắc — không quầng blur.
                .shadow(color: .black.opacity(0.55), radius: 10, y: 8)
                .scaleEffect(vm.isPlaying ? (artHover ? 1.03 : 1) : 0.93)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: vm.isPlaying)
                .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        }
        .buttonStyle(CompactCtlStyle())
        .padding(.leading, 8)   // lùi vào cho thẳng hàng với lề nội dung bên dưới
        .help("Mở app đang phát")
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { artHover = h } }
    }

    /// ⏮ ⏯ ⏭ ở giữa (nút phát là vòng tròn trắng), âm lượng + hàng đợi ở bên phải.
    private var musicTransport: some View {
        ZStack {
            // << ⏯ >> canh GIỮA hàng.
            HStack(spacing: 6) {
                SkipButton(symbol: "backward.fill", help: "Bài trước") { vm.previous() }
                Button { vm.playPause() } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white))
                }
                .buttonStyle(CompactCtlStyle())
                SkipButton(symbol: "forward.fill", help: "Bài tiếp") { vm.next() }
            }
            // Âm lượng sát trái, danh sách phát sát phải.
            HStack(spacing: 2) {
                if vm.track?.volume != nil {
                    // Bấm loa → thanh trượt ngắn mọc ra ngay cạnh (không che hàng nút);
                    // bấm lại hoặc để yên vài giây thì thu vào.
                    ctlButton(volumeGlyph(volFraction ?? vm.track?.volume ?? 0), 13) {
                        withAnimation(revealSpring) { showVolume.toggle() }
                        if showVolume { scheduleVolumeAutoHide() } else { volumeAutoHide?.cancel() }
                    }
                    if showVolume {
                        volumeSlider(level: volFraction ?? vm.track?.volume ?? 0)
                            .frame(width: 110)
                            // Mọc ra từ mép trái CỦA CHÍNH NÓ (scale neo .leading) — không dùng
                            // .move(edge:): nó trượt từ mép container và lướt đè lên icon loa.
                            .transition(.opacity.combined(with: .scale(scale: 0.3, anchor: .leading)))
                    }
                }
                Spacer(minLength: 0)
                ctlButton(vm.showList ? "list.bullet.circle.fill" : "list.bullet", 15) {
                    withAnimation(vm.showList ? closeSpring : revealSpring) { vm.toggleList() }
                }
            }
        }
    }

    // Queue / playlist pulled from the playing YouTube tab.
    // The header + player controls above stay fixed; only the rows scroll here.
    @ViewBuilder private var queueList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(.white.opacity(0.10))
            HStack {
                Text("Up Next").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if !vm.playlist.isEmpty {
                    Text("\(vm.playlist.count)").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            if vm.playlist.isEmpty {
                Text("Không có danh sách\n(mở video YouTube có playlist / up-next)")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.playlist) { item in queueRow(item) }
                    }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .edgeFade(.vertical, 24, leading: false)
            }
        }
    }

    private func queueRow(_ item: MediaListItem) -> some View {
        Button { vm.playListItem(item) } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.06))
                    if let s = item.thumbnailURL, let url = URL(string: s) {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.clear }
                    }
                    if item.isCurrent {
                        Rectangle().fill(.black.opacity(0.35))
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 27)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 11, weight: item.isCurrent ? .semibold : .regular))
                        .foregroundStyle(item.isCurrent ? alcoveRed : .white.opacity(0.92))
                        .lineLimit(1)
                    Text([item.channel, item.duration].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(hoveredQueueID == item.id ? 0.09 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(CompactCtlStyle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredQueueID = h ? item.id : (hoveredQueueID == item.id ? nil : hoveredQueueID)
            }
        }
    }

    private func placeholderPanel(_ tab: RailTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    Text("Coming soon").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notifications tab

    @ViewBuilder private var notificationsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.notificationsPermissionDenied {
                notificationsPermissionPrompt
            } else if vm.notifications.isEmpty {
                NotchEmptyState(symbol: "bell.slash", title: "Chưa có thông báo",
                                hint: "Thông báo mới từ các app sẽ hiện ở đây")
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.notificationGroups) { group in
                            notificationGroupView(group)
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .edgeFade(.vertical, 24, leading: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// An app's notifications. Collapsed → a "pile" (newest card + peeking edges
    /// + count badge) that expands on click. Single-notification apps skip the
    /// pile and render as one plain card.
    private func notificationGroupView(_ group: NotificationGroup) -> some View {
        let expanded = expandedGroups.contains(group.bundleId)
        let count = group.records.count
        return Group {
            if count <= 1 {
                notificationCard(group.records[0], action: { vm.openNotification(group.records[0]) })
            } else if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Collapse control at the TOP so it's always reachable even
                    // when the expanded stack overflows the fixed panel height.
                    Button { toggleGroup(group.bundleId) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                            Text("Thu gọn \(count) thông báo").font(.system(size: 9.5, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(group.records) { rec in
                        notificationCard(rec, action: { vm.openNotification(rec) })
                    }
                }
            } else {
                // Collapsed pile: newest card on top, with real (space-reserving)
                // peeking edges below so nothing clips into the next group.
                Button { toggleGroup(group.bundleId) } label: {
                    VStack(spacing: 3) {
                        notificationCard(group.records[0], action: nil)
                            .overlay(alignment: .topTrailing) {
                                Text("\(count)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Circle().fill(.white.opacity(0.92)))
                                    .padding(6)
                            }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .frame(height: 4).padding(.horizontal, 10)
                        if count > 2 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.white.opacity(0.05))
                                .frame(height: 4).padding(.horizontal, 20)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleGroup(_ bundleId: String) {
        withAnimation(revealSpring) {
            if expandedGroups.contains(bundleId) { expandedGroups.remove(bundleId) }
            else { expandedGroups.insert(bundleId) }
        }
    }

    /// One notification as a horizontal card: app icon on the left, two sliding
    /// text lines on the right (no app name — the icon carries identity).
    private func notificationCard(_ rec: NotificationRecord, action: (() -> Void)?) -> AnyView {
        // Fresh arrivals scroll a few times; older items scroll once on view.
        let loops = Date().timeIntervalSince(rec.date) < 60 ? 3 : 1
        let body = HStack(alignment: .center, spacing: 9) {
            Image(nsImage: vm.notificationIcon(rec.bundleId))
                .resizable().interpolation(.high).frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SlidingText(text: rec.title.isEmpty ? rec.appName : rec.title,
                                font: .system(size: 11.5, weight: .semibold),
                                color: .white.opacity(0.92), loops: loops, lineHeight: 15)
                    Text(Self.relativeTime(rec.date))
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                }
                if !rec.detailLine.isEmpty {
                    SlidingText(text: rec.detailLine,
                                font: .system(size: 10.5, weight: .regular),
                                color: .white.opacity(0.5), loops: loops, lineHeight: 14)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        let card = GlassCard { body }
        if let action {
            return AnyView(Button(action: action) { card }.buttonStyle(.plain))
        }
        return AnyView(card)
    }

    private var notificationsPermissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cần Full Disk Access")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            Text("Để hiện thông báo hệ thống, cấp quyền Full Disk Access cho Just a Notch trong System Settings.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Mở System Settings")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Compact Vietnamese relative time ("5 phút trước", "2 giờ trước").
    private static func relativeTime(_ date: Date) -> String {
        let s = max(0, Date().timeIntervalSince(date))
        if s < 60 { return "vừa xong" }
        if s < 3600 { return "\(Int(s / 60)) phút trước" }
        return "\(Int(s / 3600)) giờ trước"
    }

    // Bright hairline between rail and body (brighter in the middle).
    private var divider: some View {
        Capsule()
            .fill(LinearGradient(colors: [.white.opacity(0.02), .white.opacity(0.26), .white.opacity(0.02)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 1).frame(maxHeight: .infinity)
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            ctlButton("backward.fill", 14) { vm.previous() }; Spacer()
            ctlButton(vm.isPlaying ? "pause.fill" : "play.fill", 18) { vm.playPause() }; Spacer()
            ctlButton("forward.fill", 14) { vm.next() }; Spacer()
            if vm.track?.volume != nil {
                ctlButton(volumeGlyph(volFraction ?? vm.track?.volume ?? 0), 13) {
                    withAnimation(revealSpring) { showVolume = true }
                    scheduleVolumeAutoHide()
                }
                Spacer()
            }
            ctlButton(vm.showList ? "list.bullet.circle.fill" : "list.bullet", 15) {
                withAnimation(vm.showList ? closeSpring : revealSpring) { vm.toggleList() }
            }
        }
    }

    // Volume of the playing source itself (Music / Spotify / the YouTube tab),
    // independent of the system volume. Occupies the transport row's slot while
    // shown, and slides back after a few idle seconds.
    private var volumeRow: some View {
        let level = volFraction ?? vm.track?.volume ?? 0
        return HStack(spacing: 2) {
            // Back to the transport controls, or mute in one tap.
            ctlButton("chevron.left", 12) {
                volumeAutoHide?.cancel()
                withAnimation(revealSpring) { showVolume = false }
            }
            ctlButton(volumeGlyph(level), 13) {
                setVolumeFromUI(level > 0 ? 0 : 0.5)
            }
            volumeSlider(level: level)
                .padding(.leading, 4)
            ctlButton("speaker.wave.3.fill", 12) { setVolumeFromUI(1) }
        }
    }

    /// Applies a volume from any control, holding the shown value against the
    /// 1s poll and restarting the auto-hide countdown.
    private func setVolumeFromUI(_ level: Double) {
        volHold?.cancel()
        let f = min(1, max(0, level))
        volFraction = f
        lastSentVolume = f
        vm.setVolume(f)
        holdVolume()
        scheduleVolumeAutoHide()
    }

    /// Hides the volume strip after a few seconds without any adjustment.
    private func scheduleVolumeAutoHide() {
        volumeAutoHide?.cancel()
        let work = DispatchWorkItem {
            withAnimation(revealSpring) { showVolume = false }
        }
        volumeAutoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func volumeGlyph(_ level: Double) -> String {
        if level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// Holds the dragged value briefly so the 1s poll doesn't snap it back.
    private func holdVolume() {
        let work = DispatchWorkItem { volFraction = nil }
        volHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func volumeSlider(level: Double) -> some View {
        let dragging = volFraction != nil
        let r: CGFloat = 5
        return GeometryReader { g in
            let usable = max(1, g.size.width - 2 * r)
            let cx = r + CGFloat(level) * usable
            let d: CGFloat = dragging ? 10 : 7
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                Capsule().fill(.white.opacity(0.75)).frame(width: max(3, cx), height: 3)
                Circle().fill(.white.opacity(0.9)).frame(width: d, height: d)
                    .offset(x: cx - d / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        volHold?.cancel()
                        volumeAutoHide?.cancel()
                        let f = min(1, max(0, Double((v.location.x - r) / usable)))
                        volFraction = f
                        // Apply while dragging so you hear the change immediately.
                        // Only send on a visible step; the service coalesces the
                        // rest so a slow round-trip can't lag behind the thumb.
                        if abs(f - lastSentVolume) > 0.01 {
                            lastSentVolume = f
                            vm.setVolume(f, live: true)
                        }
                    }
                    .onEnded { v in
                        setVolumeFromUI(Double((v.location.x - r) / usable))
                    }
            )
        }
        .frame(height: 10)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
    }

    private var scrubber: some View {
        let progress = CGFloat(scrubFraction ?? Double(vm.track?.progress ?? 0))
        let dragging = scrubFraction != nil
        // Reserve the largest thumb's radius at each end so the knob never spills
        // past the track (which the ScrollView / notch clip would otherwise cut at
        // 0% and 100%). Progress maps into the inset track only.
        let r: CGFloat = 6.5
        return GeometryReader { g in
            let w = g.size.width
            let usable = max(1, w - 2 * r)
            let cx = r + progress * usable           // thumb centre, always in [r, w-r]
            let d: CGFloat = dragging ? 13 : 9
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(.white).frame(width: max(3, cx), height: 3)
                Circle().fill(.white).frame(width: d, height: d)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: cx - d / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())   // whole strip is draggable/clickable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        scrubHold?.cancel()
                        scrubFraction = min(1, max(0, Double((v.location.x - r) / usable)))
                    }
                    .onEnded { v in
                        let f = min(1, max(0, Double((v.location.x - r) / usable)))
                        scrubFraction = f
                        vm.seek(toFraction: f)
                        // Hold the shown position ~2.5s until the poll reflects the seek.
                        let work = DispatchWorkItem { scrubFraction = nil }
                        scrubHold = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
                    }
            )
        }
        .frame(height: 12)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
    }

    private func ctlButton(_ name: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        CompactCtlButton(name: name, size: size, action: action)
    }
}

// Compact transport button: a soft circular highlight fades in under the glyph
// on hover, and the whole thing dips + brightens on press.
private struct CompactCtlButton: View {
    let name: String
    let size: CGFloat
    var hitHeight: CGFloat = 30
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(hovering ? 0.18 : 0))
                    .frame(width: 26, height: 26)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .blur(radius: 4)
                Image(systemName: name)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.9))
            }
            // Generous invisible hit target so you don't have to nail the glyph.
            .frame(width: size + 16, height: hitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactCtlStyle())
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = h }
        }
    }
}

// Springy press feedback for the compact transport buttons.
private struct CompactCtlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Rail tabs

enum RailTab: String, CaseIterable, Identifiable {
    case music, notifications, calendar, clipboard, timer, learn, settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .music:         return "music.note"
        case .notifications: return "bell.fill"
        case .calendar:      return "calendar"
        case .clipboard:     return "doc.on.clipboard"
        case .timer:         return "timer"
        case .learn:         return "graduationcap.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .music:         return "Đang phát"
        case .notifications: return "Thông báo"
        case .calendar:      return "Lịch"
        case .clipboard:     return "Clipboard"
        case .timer:         return "Hẹn giờ"
        case .learn:         return "Học"
        case .settings:      return "Cài đặt"
        }
    }
}

// Nút ⚙️/✕ ở wing phải tab Timer: to hơn 10%, sáng + phóng nhẹ khi hover.
private struct WingGearButton: View {
    let open: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: open ? "xmark" : "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))          // 12 → 13 (~+10%)
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.7))
                .frame(width: 26, height: 26)                        // 24 → 26 (~+10%)
                .background(Circle().fill(.white.opacity(hovering ? 0.16 : 0.08)))
                .scaleEffect(hovering ? 1.12 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - ThemeCarousel
//
// Vertical, infinite-loop, focus-centre rail. Fully custom (no ScrollView →
// no scrollbar, no one-way snapping bugs). `offset` is a continuous position
// in points; the tab nearest the centre is scaled up + lit and drives
// `selection`. Indices wrap with modulo, so it scrolls forever both ways.

struct ThemeCarousel: View {
    let tabs: [RailTab]
    @Binding var selection: RailTab
    var reduceMotion: Bool

    private let itemSize: CGFloat = 34
    private let spacing: CGFloat = 10
    private var slot: CGFloat { itemSize + spacing }
    private var count: Int { tabs.count }

    // The whole rail column: wide enough for the icon + its glow, symmetric so
    // the focused item sits dead-centre (not shoved against the divider).
    private let railWidth: CGFloat = 46
    private let stepThreshold: CGFloat = 3.5  // accumulated delta needed for one tab step
    private let stepCooldown: Double = 0.16    // min seconds between steps in a long scroll

    @State private var offset: CGFloat = 0          // scrolled distance, in points
    @State private var scrollAcc: CGFloat = 0       // delta accumulated toward the next step
    @State private var stepping = false             // cooldown gate

    private func wrap(_ i: Int) -> RailTab { tabs[((i % count) + count) % count] }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let center = h / 2
            let f = offset / slot                    // centred virtual index (fractional)
            let span = Int(ceil((h / 2) / slot)) + 2 // how many items reach past each edge

            ZStack {
                ForEach((Int(f.rounded()) - span)...(Int(f.rounded()) + span), id: \.self) { vi in
                    cell(vi: vi, f: f, center: center)
                }
            }
            .frame(width: railWidth, height: h)
            .contentShape(Rectangle())
            .background(
                ScrollWheelCatcher(
                    onScroll: { dy in handleScroll(dy) },
                    onEnded: { scrollAcc = 0 }
                )
            )
        }
        .frame(width: railWidth)
        .onAppear {
            offset = CGFloat(tabs.firstIndex(of: selection) ?? 0) * slot
        }
        // Selection changed from outside (keyboard 1/2/3) → snap the rail to it.
        .onChange(of: selection) { _, newSel in
            guard let i = tabs.firstIndex(of: newSel) else { return }
            let target = CGFloat(i) * slot
            if abs(offset - target) > 0.5 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { offset = target }
            }
        }
    }

    // One scroll "tick" past the threshold snaps exactly one tab further.
    private func handleScroll(_ dy: CGFloat) {
        // Reversing direction: drop any stale accumulation from the previous
        // direction so a leftover can't fire one step the wrong way first.
        if scrollAcc != 0, (dy > 0) != (scrollAcc > 0) { scrollAcc = 0 }
        scrollAcc += dy
        guard !stepping, abs(scrollAcc) >= stepThreshold else { return }
        let dir = scrollAcc > 0 ? 1 : -1
        scrollAcc = 0
        stepping = true
        step(dir)
        DispatchQueue.main.asyncAfter(deadline: .now() + stepCooldown) { stepping = false }
    }

    private func step(_ dir: Int) {
        let current = Int((offset / slot).rounded())
        snapCenter(on: current + dir)
    }

    @ViewBuilder
    private func cell(vi: Int, f: CGFloat, center: CGFloat) -> some View {
        let dy: CGFloat = CGFloat(vi) - f
        let dist: CGFloat = abs(dy)
        let focus: Double = Double(max(CGFloat(0), 1 - dist / 1.6))   // 1 centred → 0 far
        let y: CGFloat = center + dy * slot
        // Fade an item out before it reaches the top/bottom edge (replaces a
        // hard clip, which was cutting the glow).
        let room: CGFloat = center - abs(y - center)
        let edgeFade: Double = Double(max(CGFloat(0), min(CGFloat(1), room / (itemSize * 0.6))))
        icon(wrap(vi), focus: focus)
            .opacity(edgeFade)
            .frame(width: railWidth, height: slot)   // full-width, tall hit target
            .contentShape(Rectangle())
            .position(x: railWidth / 2, y: y)
            .onTapGesture { snapCenter(on: vi) }
    }

    private func snapCenter(on vi: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            offset = CGFloat(vi) * slot
        }
        updateSelection(at: vi)
    }

    private func updateSelection(at index: Int? = nil) {
        let i = index ?? Int((offset / slot).rounded())
        let tab = wrap(i)
        if tab != selection { selection = tab }
    }

    private func icon(_ tab: RailTab, focus: Double) -> some View {
        let pill: Double = max(0, (focus - 0.62) / 0.38)          // only the centred item lights up
        let scale: CGFloat = reduceMotion ? 1 : CGFloat(0.82 + 0.18 * focus)
        let tint: Color = pill > 0.5 ? Color.black : Color.white.opacity(0.32 + 0.4 * focus)
        let selfOpacity: Double = reduceMotion ? (focus > 0.5 ? 1 : 0.45) : (0.45 + 0.55 * focus)
        return Image(systemName: tab.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: itemSize, height: itemSize)
            .background(
                Circle().fill(.white).opacity(pill)
                    .shadow(color: .white.opacity(0.9 * pill), radius: 2.5 * pill)   // subtle white glow (kept tight so it doesn't clip on the notch edge)
            )
            .scaleEffect(scale)
            .opacity(selfOpacity)
    }
}

// Captures two-finger / wheel scrolling over the rail without a scroll bar.
// Click-transparent so the SwiftUI icons keep receiving taps.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll; v.onEnded = onEnded
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) {
        v.onScroll = onScroll; v.onEnded = onEnded
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        private var monitor: Any?

        // Never intercept mouse clicks — taps must fall through to the icons.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // The notch is a non-activating panel, so scrollWheel doesn't reach us
        // via the responder chain. Catch it with a local monitor (same pattern
        // the window controller uses for mouse-move / click), scoped to when the
        // pointer is actually over the rail.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                    // So theo vị trí chuột trên màn hình, không theo e.window: ở dạng pill,
                    // cửa sổ bắt kéo-thả (shelf catcher) nằm đè lên vùng này và nhận event.
                    guard let self, let win = self.window else { return e }
                    let local = self.convert(self.bounds, to: nil)
                    guard win.convertToScreen(local).contains(NSEvent.mouseLocation) else { return e }
                    // Ignore trackpad momentum — only active finger/wheel scrolling
                    // drives tab steps, so leftover momentum in one direction can't
                    // fire a step after the user has already reversed.
                    if e.momentumPhase != [] {
                        if e.momentumPhase == .ended { self.onEnded?() }
                        return nil
                    }
                    let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.deltaY * 6
                    let dx = e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.deltaX * 6
                    // Natural direction: content up/left → advance to the next tab.
                    self.onScroll?(abs(dx) > abs(dy) ? -dx : -dy)
                    if e.phase == .ended || e.phase == .cancelled {
                        self.onEnded?()
                    }
                    return nil   // consume so the right-hand panel doesn't also scroll
                }
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

/// Vòng quay tab nằm ngang: tab đang chọn luôn ở giữa (viên tròn trắng),
/// hai bên nhỏ + mờ dần. Cuộn/vuốt để xoay, bấm tab bên cạnh để xoay tới nó.
struct TabWheel: View {
    let tabs: [RailTab]
    @Binding var selection: RailTab
    var reduceMotion: Bool

    /// Chỉ số "ảo" không giới hạn → các ô trượt liên tục khi xoay vòng.
    @State private var vIndex = 0
    @State private var acc: CGFloat = 0
    @State private var cooling = false

    private let slot: CGFloat = 26
    private let reach = 2   // số tab hiện mỗi bên

    private func wrap(_ i: Int) -> RailTab { tabs[((i % tabs.count) + tabs.count) % tabs.count] }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            ZStack {
                ForEach((vIndex - reach - 1)...(vIndex + reach + 1), id: \.self) { vi in
                    cell(vi).position(x: cx + CGFloat(vi - vIndex) * slot, y: cy)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .background(ScrollWheelCatcher(onScroll: handle, onEnded: { acc = 0 }))
        }
        .onAppear { vIndex = tabs.firstIndex(of: selection) ?? 0 }
        .onChange(of: selection) { _, new in
            // Đổi tab từ nơi khác (phím tắt) → xoay theo đường ngắn nhất.
            guard wrap(vIndex) != new, let t = tabs.firstIndex(of: new) else { return }
            let cur = ((vIndex % tabs.count) + tabs.count) % tabs.count
            var delta = t - cur
            if delta > tabs.count / 2 { delta -= tabs.count }
            if delta < -tabs.count / 2 { delta += tabs.count }
            withAnimation(anim) { vIndex += delta }
        }
    }

    @ViewBuilder private func cell(_ vi: Int) -> some View {
        let dist: CGFloat = abs(CGFloat(vi - vIndex))
        let tab: RailTab = wrap(vi)
        let on: Bool = vi == vIndex
        let visible: Bool = dist <= CGFloat(reach)
        Button { rotate(to: vi) } label: {
            Image(systemName: tab.icon)
                .font(.system(size: on ? 12 : 11, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.7))
                .frame(width: on ? 26 : 22, height: on ? 26 : 22)
                .background(Circle().fill(on ? Color.white : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .scaleEffect(1 - 0.14 * min(dist, 3))
        .opacity(visible ? 1 - 0.32 * Double(dist) : 0)
        .allowsHitTesting(visible)
    }

    private var anim: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.8)
    }

    private func rotate(to vi: Int) {
        withAnimation(anim) { vIndex = vi }
        selection = wrap(vi)
    }

    private func handle(_ d: CGFloat) {
        if acc != 0, (d > 0) != (acc > 0) { acc = 0 }
        acc += d
        guard !cooling, abs(acc) >= 4 else { return }
        let step = acc > 0 ? 1 : -1
        acc = 0; cooling = true
        rotate(to: vIndex + step)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { cooling = false }
    }
}

/// Nút << >> của tab Đang phát: hover sáng + phóng nhẹ, nhấn lún.
private struct SkipButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            // Kiểu << >> trần, không nền tròn: hover sáng hẳn + phóng nhẹ.
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))   // 18 → 11 (−40%)
                .foregroundStyle(.white.opacity(hover ? 1 : 0.8))
                .frame(width: 34, height: 34)
                .scaleEffect(hover ? 1.12 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(CompactCtlStyle())
        .help(help)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hover)
    }
}

/// Dựng nội dung nặng SAU khi hiệu ứng chuyển tab chạy xong (~0.2s) rồi mờ vào —
/// tránh khựng giữa lúc vuốt (việc dựng nhiều control AppKit chen vào khung hình).
struct DeferredMount<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var ready = false

    var body: some View {
        ZStack {
            if ready { content().transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.2)) { ready = true }
        }
    }
}

/// Ambient light của thông báo (chill): quầng màu dịu toả lên từ đáy, hiện ra chậm,
/// rồi "thở" nhẹ và trôi rất chậm qua lại — không có dải sáng chạy ngang.
struct AmbientSweep: View {
    let tint: Color
    let key: String
    let reduceMotion: Bool
    @State private var shown = false
    @State private var breathe = false
    @State private var drift = false

    var body: some View {
        GeometryReader { g in
            RadialGradient(colors: [tint.opacity(breathe ? 0.34 : 0.22), tint.opacity(0.06), .clear],
                           center: UnitPoint(x: drift ? 0.62 : 0.38, y: 1.05),
                           startRadius: 0, endRadius: g.size.width * 0.6)
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .onAppear { start() }
        .onChange(of: key) { _, _ in
            // Thông báo mới: hạ nhẹ rồi hiện lại từ từ.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = false }
            start()
        }
    }

    private func start() {
        withAnimation(.easeInOut(duration: 1.2)) { shown = true }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { breathe = true }
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
    }
}

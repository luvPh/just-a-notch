import SwiftUI

private let alcoveRed = Color(red: 0.96, green: 0.36, blue: 0.33)

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    // Observe the timer directly so compact-wing geometry + the countdown badge
    // refresh on its 1s ticks (nested ObservableObjects don't republish `vm`).
    @ObservedObject private var timer: TimerService
    @ObservedObject private var settings = AppSettings.shared

    init(vm: NotchViewModel) {
        _vm = ObservedObject(wrappedValue: vm)
        _timer = ObservedObject(wrappedValue: vm.timer)
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var railTab: RailTab = .music

    // System setting OR the user's manual override in Settings → Motion.
    private var reduceMotion: Bool { systemReduceMotion || settings.forceReduceMotion }

    // Music + Settings are always present; the middle tabs follow user toggles.
    private var visibleTabs: [RailTab] {
        var t: [RailTab] = [.music]
        if settings.showFiles { t.append(.files) }
        if settings.showNotifications { t.append(.notifications) }
        if settings.showCalendar { t.append(.calendar) }
        if settings.showClipboard { t.append(.clipboard) }
        if settings.showTimer { t.append(.timer) }
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
    // Notifications: which app-piles are expanded (by bundleId).
    @State private var expandedGroups: Set<String> = []
    // Local keyDown monitor active while the panel is expanded (installed on appear).
    @State private var keyMonitor: Any?

    private var openSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.8)
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
                .scaleEffect(vm.hovering && !vm.expanded ? 1.03 : 1.0, anchor: .top)
                .offset(x: vm.centerXOffset)
                .onHover { vm.hovering = $0 }
                .animation(hoverSpring, value: vm.hovering)
                .animation(revealSpring, value: vm.compactState)
                .animation(openSpring, value: vm.expanded)
                .animation(openSpring, value: vm.showList)
                // Notch phình ra/thu lại mềm khi mở tab cao hơn (Lịch).
                .animation(openSpring, value: vm.panelWantsTall)
                // Lịch co/giãn theo số hàng tuần của tháng (5 vs 6 tuần).
                .animation(openSpring, value: vm.surfaceHeight)
                // Files mở rộng cả chiều ngang (ẩn sidebar) — phình mềm sang hai bên.
                .animation(openSpring, value: vm.surfaceWidth)
                .animation(revealSpring, value: vm.showingHUD)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
        // Global hotkey ⌃⌥1/2/3 → nhảy tới tab thứ N trong danh sách đang hiển thị.
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
        guard vm.expanded else { return false }
        // Never steal keys while editing a text field (rename / new catalogue).
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        // Leave app-level combos (⌘Q, ⌘W, …) alone — only bare keys are shortcuts.
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty else { return false }

        switch event.keyCode {
        case 53:                                    // Esc → collapse
            withAnimation(openSpring) { vm.collapse() }
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
        vm.panelWantsTall = (tab == .calendar || tab == .settings)
        vm.filesTabActive = (tab == .files)
        vm.calTabActive = (tab == .calendar)
        vm.notifTabActive = (tab == .notifications)
        if tab != .files { vm.filesSelCount = 0 }
        if vm.showList { withAnimation(openSpring) { vm.showList = false } }
    }

    private var surface: some View {
        let shape = NotchShape(bottom: vm.bottomRadius, inverse: vm.topRadius)
        return ZStack(alignment: .top) {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.5), radius: vm.expanded ? 26 : 10, y: vm.expanded ? 14 : 5)

            if vm.showingHUD {
                hudBanner.transition(.blurFade)
            } else if vm.expanded {
                player.transition(.blurFade)
            } else if vm.hasMedia {
                compact.transition(.blurFade)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            if vm.showingHUD { vm.openSourceApp(); return }
            if !vm.expanded { vm.refreshMedia(); withAnimation(openSpring) { vm.expanded = true } }
        }
        // Chỉ thu notch khi bấm vùng header 220×40px ở giữa trên (trên lõi camera).
        // Hai wing hai bên để trống cho các nút chức năng, không lỡ tay thu app.
        .overlay(alignment: .top) {
            if vm.expanded {
                Color.clear
                    .frame(width: 220, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(openSpring) { vm.collapse() } }
            }
        }
        // Số favorite đang chọn (tab Files nhỏ) — đặt ở WING TRÁI, ngang lõi camera.
        .overlay(alignment: .topLeading) {
            if vm.expanded && vm.filesTabActive && !vm.filesExpanded && vm.filesSelCount > 0 {
                HStack(spacing: 4) {
                    Text("\(vm.filesSelCount)").font(.system(size: 12, weight: .bold))
                    Image(systemName: "doc.fill").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.75, green: 0.6, blue: 1.0))
                .shadow(color: Color(red: 0.66, green: 0.46, blue: 1.0).opacity(0.85), radius: 6)
                .shadow(color: Color(red: 0.66, green: 0.46, blue: 1.0).opacity(0.5), radius: 12)
                .padding(.leading, 46).padding(.top, 12)
                .allowsHitTesting(false)
                .transition(.opacity)
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
            HStack(spacing: 8) {
                SourceIcon(sourceApp: vm.track?.sourceAppName ?? "", size: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.openSourceMediaApp() }
                if vm.compactState == .reading, let track = vm.track {
                    MarqueeText(text: track.title, viewport: vm.titleViewport,
                                onPanDuration: vm.scheduleTitleRetraction)
                }
            }
            .padding(.leading, 13)
            .frame(width: vm.leftReveal, alignment: .leading)
            .clipped()

            Color.clear.frame(width: vm.coreWidth)

            compactRight
                .padding(.trailing, 15)
                .frame(width: vm.rightReveal, alignment: .trailing)
                .clipped()
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
    }

    // Right wing: the soundwave morphs into ◀ ⏯ ▶ transport controls on hover.
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
        .padding(.top, vm.notchHeight + 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(width: vm.hudWidth, height: vm.hudHeight, alignment: .leading)
    }

    // MARK: Expanded Alcove player

    private var player: some View {
        // spacing 0: tự kiểm soát từng khoảng để rail↔divider luôn 14 (icon căn giữa
        // như cũ), chỉ khoảng divider↔content mới thu hẹp ở tab Files.
        HStack(alignment: .top, spacing: 0) {
            // Ẩn sidebar (rail + divider) khi Files mở rộng — dồn toàn bộ chiều ngang cho tab.
            if !vm.filesWide {
                ThemeCarousel(tabs: visibleTabs, selection: $railTab, reduceMotion: reduceMotion)
                    .onChange(of: railTab) { _, newTab in
                        vm.panelWantsTall = (newTab == .calendar || newTab == .settings)
                        vm.filesTabActive = (newTab == .files)
                        vm.calTabActive = (newTab == .calendar)
                        vm.notifTabActive = (newTab == .notifications)
                        if newTab != .files { vm.filesSelCount = 0 }   // rời tab Files → xoá đếm
                        // Leaving music collapses the queue so the window shrinks back
                        // to the default tab height instead of staying inflated.
                        if vm.showList { withAnimation(openSpring) { vm.showList = false } }
                    }
                    .padding(.top, vm.notchHeight + 8)   // sidebar LUÔN dưới camera, không đổi theo tab
                    .padding(.trailing, 14)              // khoảng rail↔divider cố định
                    .transition(.blurFade)
                divider
                    .padding(.top, vm.notchHeight + 8)
                    .padding(.trailing, vm.filesTabActive ? 6 : 14)   // divider↔content: files thu hẹp
                    .transition(.opacity)
            }
            // Player controls stay fixed at the top; only the queue list scrolls
            // (the list has its own ScrollView). Fill the fixed window height so
            // that inner ScrollView gets a bounded height to scroll within.
            content
                .id(railTab)                 // re-run the transition on tab change
                .transition(.blurFade)
                // Tab Files: content đẩy lên hàng wing (chừa 6px); tab khác chừa đủ camera.
                .padding(.top, vm.filesTabActive ? 6 : vm.notchHeight + 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.82),
                           value: railTab)
        }
        // Bỏ inset trái của rail khi ẩn sidebar để Files dùng trọn chiều ngang.
        .padding(.leading, vm.filesWide ? 12 : 34).padding(.trailing, vm.filesTabActive ? 12 : 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(openSpring, value: vm.filesWide)
    }

    // The right-hand panel — swaps with the centered carousel tab.
    @ViewBuilder private var content: some View {
        switch railTab {
        case .music:         musicPanel
        case .notifications: notificationsPanel
        case .calendar:      calendarPanel
        case .files:         filesPanel
        case .clipboard:     ClipboardPanel(store: vm.clipboard)
        case .timer:         TimerPanel(timer: vm.timer, settings: AppSettings.shared)
        case .settings:      SettingsPanel(settings: settings, vm: vm)
        default:             placeholderPanel(railTab)
        }
    }

    private var calendarPanel: some View {
        CalendarPanel(mode: $calMode, anchor: $calAnchor,
                      expanded: Binding(get: { vm.calExpanded },
                                        set: { vm.calExpanded = $0 }),
                      onRowsChange: { vm.calendarRows = $0 })
    }

    private var filesPanel: some View {
        FilesPanel(store: vm.fileStore,
                   expanded: Binding(get: { vm.filesExpanded },
                                     set: { vm.filesExpanded = $0 }),
                   pinned: Binding(get: { vm.pinnedOpen },
                                   set: { vm.pinnedOpen = $0 }),
                   selCount: Binding(get: { vm.filesSelCount },
                                     set: { vm.filesSelCount = $0 }))
    }

    private var musicPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { vm.openSourceMediaApp() } label: {
                    Artwork(data: vm.track?.artworkData, corner: 7).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.track?.title ?? "Not playing").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(vm.track?.artist ?? vm.track?.sourceAppName ?? "—")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 4)
                OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion, bars: 6)
                    .frame(width: 18, height: 11)
            }
            scrubber
            HStack(spacing: 0) {
                ctlButton("backward.fill", 14) { vm.previous() }; Spacer()
                ctlButton(vm.isPlaying ? "pause.fill" : "play.fill", 18) { vm.playPause() }; Spacer()
                ctlButton("forward.fill", 14) { vm.next() }; Spacer()
                ctlButton(vm.showList ? "list.bullet.circle.fill" : "list.bullet", 15) {
                    withAnimation(revealSpring) { vm.toggleList() }
                }
            }
            .padding(.horizontal, 4)

            if vm.showList {
                queueList.transition(.blurFade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text("Chưa có thông báo")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                notificationCard(group.records[0], action: { vm.openApp(bundleId: group.records[0].bundleId) })
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
                        notificationCard(rec, action: { vm.openApp(bundleId: rec.bundleId) })
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
                            .fill(.white.opacity(0.09))
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
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
        .contentShape(Rectangle())

        if let action {
            return AnyView(Button(action: action) { body }.buttonStyle(.plain))
        }
        return AnyView(body)
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
        Button(action: action) {
            Image(systemName: name).font(.system(size: size)).foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
    }
}

// Compact transport button: a soft circular highlight fades in under the glyph
// on hover, and the whole thing dips + brightens on press.
private struct CompactCtlButton: View {
    let name: String
    let size: CGFloat
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
            .frame(width: size + 15, height: 36)
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
    case music, files, notifications, calendar, clipboard, timer, settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .music:         return "music.note"
        case .files:         return "folder.fill"
        case .notifications: return "bell.fill"
        case .calendar:      return "calendar"
        case .clipboard:     return "doc.on.clipboard"
        case .timer:         return "timer"
        case .settings:      return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .music:         return "Now Playing"
        case .files:         return "Files"
        case .notifications: return "Notifications"
        case .calendar:      return "Lịch"
        case .clipboard:     return "Clipboard"
        case .timer:         return "Timer"
        case .settings:      return "Settings"
        }
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
private struct ScrollWheelCatcher: NSViewRepresentable {
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
                    guard let self, let win = self.window, e.window === win else { return e }
                    let p = self.convert(e.locationInWindow, from: nil)
                    guard self.bounds.contains(p) else { return e }
                    // Ignore trackpad momentum — only active finger/wheel scrolling
                    // drives tab steps, so leftover momentum in one direction can't
                    // fire a step after the user has already reversed.
                    if e.momentumPhase != [] {
                        if e.momentumPhase == .ended { self.onEnded?() }
                        return nil
                    }
                    let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.deltaY * 6
                    // Natural direction: content up → advance to the next tab.
                    self.onScroll?(-dy)
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

import SwiftUI

private let alcoveRed = Color(red: 0.96, green: 0.36, blue: 0.33)

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var railTab: RailTab = .music
    // While the user is dragging the scrubber, show their position instead of the
    // (2s-polled) real progress; hold it briefly after release so it doesn't snap
    // back before the next poll catches up.
    @State private var scrubFraction: Double?
    @State private var scrubHold: DispatchWorkItem?

    private var openSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.8)
    }
    private var revealSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)
    }

    var body: some View {
        VStack(spacing: 0) {
            surface
                // Everything animates INSIDE the fixed panel, top-anchored — the surface
                // grows straight down from the notch (prototype behaviour).
                .frame(width: vm.surfaceWidth, height: vm.surfaceHeight, alignment: .top)
                .scaleEffect(vm.hovering && !vm.expanded ? 1.05 : 1.0, anchor: .top)
                .offset(x: vm.centerXOffset)
                .onHover { vm.hovering = $0 }
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: vm.hovering)
                .animation(revealSpring, value: vm.compactState)
                .animation(openSpring, value: vm.expanded)
                .animation(openSpring, value: vm.showList)
                .animation(revealSpring, value: vm.showingHUD)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion, bars: 6)
                    .frame(width: 18, height: 11)
            }
            .padding(.trailing, 15)
            .frame(width: vm.rightReveal, alignment: .trailing)
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
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
        HStack(alignment: .top, spacing: 14) {
            ThemeCarousel(tabs: RailTab.allCases, selection: $railTab, reduceMotion: reduceMotion)
                .onChange(of: railTab) { _, _ in
                    // Leaving music collapses the queue so the window shrinks back
                    // to the default tab height instead of staying inflated.
                    if vm.showList { withAnimation(openSpring) { vm.showList = false } }
                }
            divider
            // Player controls stay fixed at the top; only the queue list scrolls
            // (the list has its own ScrollView). Fill the fixed window height so
            // that inner ScrollView gets a bounded height to scroll within.
            content
                .id(railTab)                 // re-run the transition on tab change
                .transition(.blurFade)
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.82),
                           value: railTab)
        }
        .padding(.leading, 34).padding(.trailing, 24)   // small left inset so the rail's lit pill sits balanced, clear of the rounded notch edge
        .padding(.top, vm.notchHeight + 8)   // clear the physical camera + ~10px breathing room
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The right-hand panel — swaps with the centered carousel tab.
    @ViewBuilder private var content: some View {
        switch railTab {
        case .music:         musicPanel
        case .notifications: notificationsPanel
        default:             placeholderPanel(railTab)
        }
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

    private func notificationGroupView(_ group: NotificationGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: vm.notificationIcon(group.bundleId))
                    .resizable().interpolation(.high).frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(group.appName)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            ForEach(group.records) { rec in notificationRow(rec) }
        }
    }

    private func notificationRow(_ rec: NotificationRecord) -> some View {
        Button { vm.openApp(bundleId: rec.bundleId) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rec.title.isEmpty ? rec.appName : rec.title)
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.relativeTime(rec.date))
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                }
                if !rec.detailLine.isEmpty {
                    Text(rec.detailLine)
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .padding(.leading, 23)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Rail tabs

enum RailTab: String, CaseIterable, Identifiable {
    case music, files, notifications, clock, settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .music:         return "music.note"
        case .files:         return "folder.fill"
        case .notifications: return "bell.fill"
        case .clock:         return "clock.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .music:         return "Now Playing"
        case .files:         return "Files"
        case .notifications: return "Notifications"
        case .clock:         return "Clock"
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

import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ApplicationServices

/// Hosting view that responds to the first click even when the panel isn't key,
/// so the media controls work without activating the app first.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }
}

/// Owns the notch panel: positions it over the physical notch, hosts the SwiftUI
/// island, toggles mouse pass-through so only the island is interactive, and
/// collapses on outside clicks.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let vm: NotchViewModel
    private let media: MediaService
    private let notifier: NotificationService
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var hoverTimer: Timer?
    private let hotKeys = HotKeyCenter()
    private let filesPopup: FilesPopupController
    private var shelfCatcher: ShelfDropCatcher!
    private var dragWatcher: SystemDragWatcher!
    // Double-tap ⌘ → toggle notch. Global keyboard monitors ⇒ cần Accessibility.
    private var cmdTapMonitors: [Any] = []
    private var lastCmdTapTime: TimeInterval = 0
    private var cmdWasDown = false

    private var coreCenterX: CGFloat = 0
    private var screenTopY: CGFloat = 0

    init() {
        media = MediaService()
        notifier = NotificationService()
        vm = NotchViewModel(media: media, notifier: notifier)
        filesPopup = FilesPopupController(store: vm.fileStore)
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40))
        panel.contentView = ClickableHostingView(rootView: NotchRootView(vm: vm))
        panel.orderFrontRegardless()

        shelfCatcher = ShelfDropCatcher(
            onDragEnter: { [weak vm] in vm?.presentShelf() },
            onDrop: { [weak vm] urls in
                guard let vm else { return }
                for url in urls { vm.shelf.add(url: url) }
                vm.presentShelf()
            },
            onClick: { [weak vm] in
                guard let vm else { return }
                // Catcher phủ lõi notch nên phải thay luôn hành vi bấm island:
                // đang mở shelf → thu shelf; đang expand → THU notch; còn lại → mở.
                if vm.shelfActive { vm.dismissShelf(); return }
                if vm.breakActive { vm.dismissBreak(); return }
                if vm.claudeAlert != nil { vm.openClaudeAlert(); return }
                if vm.expanded { vm.collapse() }
                else { vm.refreshMedia(); vm.expanded = true }
            })

        // Bung kệ ngay khi có cú kéo file ở bất kỳ đâu, không cần hover notch.
        dragWatcher = SystemDragWatcher(
            onBegan: { [weak vm] in vm?.beginSystemFileDrag() },
            onEnded: { [weak vm] in vm?.endSystemFileDrag() })

        applyGeometry()
        layoutPanel()
        installMonitors()
        installHotKeys()
        setFKeyApps(active: AppSettings.shared.fKeyAppsEnabled)
        // Gán/bỏ gán app cũng phải đăng ký lại (phím trống được trả cho hệ thống).
        AppSettings.shared.$fKeyAppsEnabled
            .combineLatest(AppSettings.shared.$fKeyApps)
            .receive(on: RunLoop.main)
            .sink { [weak self] on, _ in self?.setFKeyApps(active: on) }
            .store(in: &bag)
        vm.start()

        // While expanded OR while a HUD banner is showing, the panel must receive
        // clicks (controls / tap-to-open-source-app). Cũng bật/tắt timer bám con trỏ.
        vm.$expanded.combineLatest(vm.$hudNotification, vm.$shelfActive, vm.$launcherOpen)
            .receive(on: RunLoop.main)
            .sink { [weak self] exp, hud, shelf, launcher in
                let live = exp || hud != nil || shelf || launcher
                if live { self?.panel.ignoresMouseEvents = false }
                self?.updateHover()
                self?.setHoverTracking(active: live)
            }.store(in: &bag)

        // While expanded the panel becomes key so keyboard shortcuts (Esc, 1/2/3,
        // Space, ←/→) route to us. A .nonactivatingPanel can be key without
        // activating the app, so the frontmost app keeps its menu bar. On collapse
        // we resign key and keyboard returns to whatever app is in front.
        // Launcher mở tính năng có ô nhập (máy tính) → panel cũng cần key để gõ phím.
        vm.$expanded.combineLatest(vm.$launcherFeature)
            .receive(on: RunLoop.main)
            .sink { [weak self] exp, feature in
                guard let self else { return }
                if exp || feature != nil {
                    self.panel.allowsKey = true
                    self.panel.makeKey()
                } else {
                    self.panel.allowsKey = false
                    self.panel.resignKey()
                }
            }.store(in: &bag)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.applyGeometry(); self?.layoutPanel() } }

        // Bật/tắt bộ phát hiện double-tap ⌘ theo Settings (emit ngay giá trị hiện tại).
        AppSettings.shared.$doubleTapCommand
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.setDoubleTapCommand(active: on) }
            .store(in: &bag)
    }

    // MARK: Geometry

    private func applyGeometry() {
        // Always target the screen that physically owns the notch (never NSScreen.main,
        // which follows the active app to an external display).
        let probe = NotchGeometryProvider(simulateNotch: false)
        let notchScreen = NSScreen.screens.first { probe.physicalNotchWidth(of: $0) != nil }
        let screen = notchScreen ?? NSScreen.main ?? NSScreen.screens.first
        let provider = NotchGeometryProvider(simulateNotch: notchScreen == nil)
        guard let screen, let geo = provider.geometry(for: screen) else { return }
        coreCenterX = geo.screenFrame.midX
        screenTopY = geo.screenFrame.maxY
        vm.coreWidth = geo.notchWidth
        // Physical notch (camera) height = safe-area top when present; 38pt fallback.
        let safeTop = screen.safeAreaInsets.top
        vm.notchHeight = safeTop > 0 ? safeTop : 38
        // Không có notch vật lý (màn ngoài / Mac không tai thỏ) → dạng pill nổi.
        vm.pillMode = notchScreen == nil
    }

    /// Surface bounding rect in screen (bottom-left origin) coordinates.
    private var islandScreenRect: CGRect {
        // Tính cả mức phóng hover (neo mép trên) để mép dưới launcher không lọt click.
        let w = vm.surfaceWidth * vm.hoverScale, h = vm.surfaceHeight * vm.hoverScale
        // Tâm bề mặt = tâm lõi + centerXOffset (0 khi canh giữa) — đúng cả khi launcher
        // nới rộng hơn hàng wing.
        let left: CGFloat = coreCenterX + vm.centerXOffset - w / 2
        let gap = vm.pillMode ? vm.pillGap : 0
        return CGRect(x: left, y: screenTopY - h - gap, width: w, height: h)
    }

    /// The panel is a FIXED transparent canvas (widest × tallest state), positioned
    /// top-centre on the notch. Every state animates purely inside SwiftUI, top-anchored
    /// — exactly like the prototype — so nothing resizes the window and motion is smooth.
    /// Mouse pass-through outside the island keeps the transparent area click-through.
    private func layoutPanel() {
        let w = panelWidth
        let h = vm.maxSurfaceHeight + vm.pillGap
        let frame = CGRect(x: coreCenterX - w / 2, y: screenTopY - h, width: w, height: h)
        panel.setFrame(frame, display: true)

        // Catcher phủ lõi notch (rộng hơn chút để dễ kéo trúng), luôn ở đỉnh màn hình.
        // Chỉ nhỉnh hơn lõi 8pt: rộng hơn sẽ che mất icon nguồn / soundwave ở hai wing.
        let cw = vm.coreWidth + 8
        let ch = vm.notchHeight + 4
        shelfCatcher.setFrame(CGRect(x: coreCenterX - cw / 2, y: screenTopY - ch, width: cw, height: ch))
        shelfCatcher.orderFront()
    }

    /// Contains the core-anchored surface at its widest asymmetric extent (reading
    /// left wing 150) and the expanded width.
    private var panelWidth: CGFloat { max(vm.coreWidth + 2 * 150, vm.maxSurfaceWidth) }

    // MARK: Mouse handling

    private func installMonitors() {
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: moved) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            self?.updateHover(); return e })
        // Bấm ra ngoài island khi đang expand thì thu notch — TRỪ tab Files (đang
        // expand): giữ panel mở để kéo-thả file/folder vào. Thu tab Files bằng cách
        // bấm vùng trống trong notch (xem onTapGesture ở surface).
        // Bấm ra ngoài khi launcher đang mở → thu launcher.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self, self.vm.launcherOpen, !self.vm.expanded else { return }
            if !self.islandScreenRect.contains(NSEvent.mouseLocation) { self.vm.closeLauncher() }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self, self.vm.expanded, !self.vm.keepOpenOnOutsideClick else { return }
            if !self.islandScreenRect.contains(NSEvent.mouseLocation) { self.vm.collapse() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            guard let self, self.vm.expanded, !self.vm.keepOpenOnOutsideClick else { return e }
            if !self.islandScreenRect.contains(NSEvent.mouseLocation) { self.vm.collapse() }
            return e
        })
    }

    /// Global hotkeys (đồng nhất dưới ⌥): mở/đóng notch, điều khiển nhạc, nhảy tab.
    private func installHotKeys() {
        let m = HotKeyCenter.opt
        hotKeys.register(keyCode: kVK_ANSI_N, modifiers: m) { [weak self] in self?.vm.toggleNotch() }
        hotKeys.register(keyCode: kVK_Space, modifiers: m) { [weak self] in self?.vm.playPause() }
        hotKeys.register(keyCode: kVK_RightArrow, modifiers: m) { [weak self] in self?.vm.next() }
        hotKeys.register(keyCode: kVK_LeftArrow, modifiers: m) { [weak self] in self?.vm.previous() }
        hotKeys.register(keyCode: kVK_ANSI_1, modifiers: m) { [weak self] in self?.vm.requestTab(1) }
        hotKeys.register(keyCode: kVK_ANSI_2, modifiers: m) { [weak self] in self?.vm.requestTab(2) }
        hotKeys.register(keyCode: kVK_ANSI_3, modifiers: m) { [weak self] in self?.vm.requestTab(3) }
        // ⌥⇧N → popup tab Files (mở rộng) canh giữa màn hình đang focus.
        hotKeys.register(keyCode: kVK_ANSI_N, modifiers: UInt32(optionKey | shiftKey)) {
            [weak self] in self?.filesPopup.toggle()
        }
    }

    /// Cài/gỡ global hotkey F1…F6 → đưa app đã gán ra trước.
    ///
    /// Dùng Carbon hotkey nên chạy ở mọi app và KHÔNG cần quyền Accessibility —
    /// nhưng cũng có nghĩa app giữ độc quyền các phím này khi bật, chức năng gốc
    /// (độ sáng, Mission Control…) tạm thời không dùng được.
    /// CHỈ giữ những phím đã gán app — phím còn trống phải trả về hệ thống, nếu
    /// không nó sẽ nuốt luôn chức năng gốc (độ sáng…) mà chẳng làm gì.
    private func setFKeyApps(active: Bool) {
        hotKeys.unregister(group: "fkeys")
        guard active else { return }
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6]
        let slots = AppSettings.shared.fKeyApps
        for (i, code) in codes.prefix(AppSettings.fKeyCount).enumerated() {
            guard let slot = slots.indices.contains(i) ? slots[i] : nil else { continue }
            hotKeys.register(keyCode: code, modifiers: 0, group: "fkeys") {
                Self.activate(bundleID: slot.bundleID)
            }
        }
    }

    /// Đưa app ra trước: nếu đang chạy thì bỏ ẩn + activate (giữ nguyên cửa sổ
    /// đang có), chưa chạy thì mở mới.
    private static func activate(bundleID: String) {
        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }) {
            app.unhide()
            app.activate(options: [.activateAllWindows])
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Cài/gỡ monitor double-tap ⌘. Khi bật lần đầu sẽ xin quyền Accessibility
    /// (global keyboard monitor không nhận sự kiện nếu chưa được cấp).
    private func setDoubleTapCommand(active: Bool) {
        for m in cmdTapMonitors { NSEvent.removeMonitor(m) }
        cmdTapMonitors.removeAll()
        lastCmdTapTime = 0; cmdWasDown = false
        guard active else { return }

        // Nhắc cấp quyền Accessibility nếu chưa có (chỉ hiện dialog khi chưa trust).
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged],
            handler: { [weak self] e in self?.handleFlags(e) }) { cmdTapMonitors.append(g) }
        let l = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            self?.handleFlags(e); return e
        }
        if let l { cmdTapMonitors.append(l) }
    }

    /// Nhận diện hai lần nhấn ⌘ (một mình) liên tiếp < 0.35s → toggle notch.
    private func handleFlags(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let down = flags.contains(.command)
        let onlyCmd = flags == [.command]
        if down, onlyCmd, !cmdWasDown {
            let t = e.timestamp
            if t - lastCmdTapTime < 0.35 { vm.toggleNotch(); lastCmdTapTime = 0 }
            else { lastCmdTapTime = t }
        }
        cmdWasDown = down
    }

    private func updateHover() {
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        // Luôn chỉ nuốt sự kiện trong đúng vùng island đang hiển thị → không có vùng
        // vô hình chặn click phía sau (kể cả khi pin). Timer bám con trỏ (khi expand)
        // giúp cập nhật kịp lúc kéo-thả để cửa sổ nhận drop khi con trỏ vào island.
        panel.ignoresMouseEvents = !inside
        let hover = inside && !vm.expanded
        if vm.hovering != hover { vm.hovering = hover }

        // Hover vào notch khi đang giữ file → bung shelf; rời hover → thu sau 1s.
        if inside {
            vm.cancelShelfHide()
            if !vm.shelfActive, !vm.expanded, !vm.showingHUD, !vm.shelf.isEmpty {
                vm.presentShelf()
            }
        } else if vm.shelfActive, !vm.systemFileDragActive {
            // Còn đang kéo file thì giữ kệ mở dù con trỏ chưa tới notch.
            vm.scheduleShelfHide()
        }
    }

    /// Timer bám vị trí con trỏ khi panel mở rộng. Vì kéo-thả từ Finder không phát
    /// mouseMoved cho app ta, nên poll nhẹ để cập nhật vùng nhận chuột kịp lúc con
    /// trỏ (đang kéo) vào island → cửa sổ nhận drop mà không cần nuốt cả canvas.
    private func setHoverTracking(active: Bool) {
        if active {
            guard hoverTimer == nil else { return }
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateHover() }
            }
            RunLoop.main.add(t, forMode: .common)
            hoverTimer = t
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    func toggleVisibility() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    func popLearn() { vm.popLearn() }

    /// Dọn thư mục temp của shelf khi thoát app.
    func cleanupShelf() { vm.shelf.cleanup() }
}

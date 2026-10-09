import XCTest
import SwiftUI
import Combine
@testable import JustANotch

/// Render notch ở các trạng thái (launcher, máy tính, lời nhắc…) ra PNG để soát
/// layout — chỉ chạy khi NOTCH_SNAP=<dir>.
@MainActor
final class NotchSnapshotCheck: XCTestCase {
    final class FakeMedia: MediaServiceProtocol {
        let currentTrack = CurrentValueSubject<MediaTrack?, Never>(nil)
        let playbackState = CurrentValueSubject<PlaybackState, Never>(.playing)
        var hasAvailableSource: Bool { true }
        func playPause() {}
        func nextTrack() {}
        func previousTrack() {}
        func seek(toFraction fraction: Double) {}
        func setVolume(_ volume: Double, live: Bool) {}
        func fetchPlaylist(_ completion: @escaping ([MediaListItem]) -> Void) { completion([]) }
        func play(item: MediaListItem) {}
        func focusSource() {}
        func refresh() {}
        func start() {}
        func stop() {}
    }
    final class FakeNotifier: NotificationServiceProtocol {
        let latestArrival = PassthroughSubject<NotificationRecord, Never>()
        let history = CurrentValueSubject<[NotificationRecord], Never>([])
        let permissionState = CurrentValueSubject<NotificationPermissionState, Never>(.granted)
        func icon(forBundle bundleId: String) -> NSImage { NSImage() }
        func start() {}
        func stop() {}
    }

    private var out: String!

    private func snap<V: View>(_ name: String, _ view: V, size: CGSize = CGSize(width: 640, height: 230),
                               wait: TimeInterval = 0.9) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(white: 0.32)))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(out!)/\(name).png"))
    }

    private func makeVM(media: Bool) -> (NotchViewModel, FakeMedia) {
        let m = FakeMedia()
        if media {
            m.currentTrack.send(MediaTrack(title: "Lofi beats to relax", artist: "Chill", album: nil,
                                           sourceAppName: "YouTube", sourceBundleID: nil, progress: 0.3,
                                           artworkData: nil))
        }
        let vm = NotchViewModel(media: m, notifier: FakeNotifier())
        vm.coreWidth = 190
        vm.notchHeight = 34
        return (vm, m)
    }

    func testSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        out = dir
        AppSettings.shared.breakSoundOn = false

        // 1. Compact có media.
        var (vm, _) = makeVM(media: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try snap("1-compact", NotchRootView(vm: vm), wait: 0.3)

        // 2. Bấm soundwave → transport.
        vm.hovering = true
        vm.showTransport()
        try snap("2-transport", NotchRootView(vm: vm), wait: 0.3)

        // 3. Hover lâu → launcher (có media).
        (vm, _) = makeVM(media: true)
        let root3 = NotchRootView(vm: vm)
        vm.hovering = true
        try snap("3-launcher-media", root3, wait: 1.4)

        // 4. Launcher không có media.
        (vm, _) = makeVM(media: false)
        vm.hovering = true
        try snap("4-launcher-nomedia", NotchRootView(vm: vm), wait: 1.4)

        // 5. Máy tính.
        UserDefaults.standard.set("150k × 3 + 2tr5", forKey: "calc.lastInput")
        (vm, _) = makeVM(media: true)
        vm.hovering = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        vm.openLauncherFeature(.calculator)
        try snap("5-calculator", NotchRootView(vm: vm), wait: 1.0)

        // 6. Máy tính đổi tiền (đợi tải tỷ giá).
        UserDefaults.standard.set("100usd", forKey: "calc.lastInput")
        CurrencyRates.shared.refreshIfStale()
        (vm, _) = makeVM(media: false)
        vm.hovering = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        vm.openLauncherFeature(.calculator)
        try snap("6-calculator-fx", NotchRootView(vm: vm), wait: 3.0)

        // 7. Lời nhắc.
        (vm, _) = makeVM(media: true)
        vm.showBreak()
        try snap("7-break", NotchRootView(vm: vm), wait: 1.2)

        // 9. Giá vàng (mạng thật).
        (vm, _) = makeVM(media: true)
        vm.hovering = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        vm.openLauncherFeature(.gold)
        try snap("9-gold", NotchRootView(vm: vm), wait: 4.0)

        // 10. Claude: chỉ báo ở wing, thông báo xong, danh sách phiên.
        let now = Date()
        let working = ClaudeSession(id: "a", cwd: "/Users/x/repo/just-a-notch", state: .working, tool: "Edit",
                                    detail: "NotchRootView.swift", message: nil, bundleID: nil,
                                    turnStartedAt: now.addingTimeInterval(-134), updatedAt: now)
        let waiting = ClaudeSession(id: "b", cwd: "/Users/x/repo/shop-api", state: .waiting, tool: "Bash",
                                    detail: nil, message: "Claude needs your permission to use Bash", bundleID: nil,
                                    turnStartedAt: now.addingTimeInterval(-40), updatedAt: now)
        let done = ClaudeSession(id: "c", cwd: "/Users/x/repo/landing", state: .done, updatedAt: now.addingTimeInterval(-300))
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [working])
        try snap("10-claude-wing", NotchRootView(vm: vm), wait: 0.6)
        (vm, _) = makeVM(media: false)
        vm._previewClaude(sessions: [waiting])
        try snap("11-claude-wing-nomedia-waiting", NotchRootView(vm: vm), wait: 0.6)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [done], alert: .done(done, duration: 154))
        try snap("12-claude-done", NotchRootView(vm: vm), wait: 0.8)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [waiting], alert: .waiting(waiting))
        try snap("13-claude-waiting", NotchRootView(vm: vm), wait: 0.8)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [waiting, working, done])
        vm.hovering = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        vm.openLauncherFeature(.claude)
        try snap("14-claude-sessions", NotchRootView(vm: vm), wait: 1.0)

        // 15–17. Codex: terminal / logo OpenAI ở wing, chờ duyệt, danh sách chung.
        let cx1 = ClaudeSession(id: "codex:s-term-1", agent: .codex, cwd: "/Users/x/repo/api", state: .working,
                                tool: "Bash", detail: "npm test", updatedAt: now)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [cx1])
        try snap("15-codex-wing", NotchRootView(vm: vm), wait: 0.8)
        let cxw = ClaudeSession(id: "codex:w", agent: .codex, cwd: "/Users/x/repo/api", state: .waiting,
                                tool: "Bash", message: "Cần duyệt: Bash", updatedAt: now)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [cxw], alert: .waiting(cxw))
        try snap("16-codex-waiting", NotchRootView(vm: vm), wait: 0.8)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [cxw, working, cx1])
        vm.hovering = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        vm.openLauncherFeature(.claude)
        try snap("17-agents-sessions", NotchRootView(vm: vm), wait: 1.0)

        // 18–19. Claude (2 phiên) + Codex (chờ duyệt) cùng chạy: hai hình cạnh nhau.
        let working2 = ClaudeSession(id: "a2", cwd: "/Users/x/repo/web", state: .working, updatedAt: now)
        (vm, _) = makeVM(media: true)
        vm._previewClaude(sessions: [cxw, working, working2])
        try snap("18-both-agents", NotchRootView(vm: vm), wait: 0.8)
        (vm, _) = makeVM(media: false)
        vm._previewClaude(sessions: [working, cx1])
        try snap("19-both-agents-nomedia", NotchRootView(vm: vm), wait: 0.8)

        // 8. Sprite phóng to từng khung để soát pixel art.
        let frames = [0, 11, 18, 30, 34].map(PixelCat.frame)
        let sheet = HStack(spacing: 24) {
            ForEach(0..<frames.count, id: \.self) { i in
                PixelSheetCell(frame: frames[i])
            }
        }.padding(20).background(.black)
        try snap("8-sprite", sheet, size: CGSize(width: 820, height: 200), wait: 0.3)

        // 20. Clipboard dạng thẻ ngang.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clip-snap-\(UUID()).json")
        let clip = ClipboardStore(fileURL: tmp, imagesDir: nil, autoPoll: false)
        clip.recordText("Palette for the autumn set: Hokusai's Prussian blue as the base, ochre and vermilion accents.")
        clip.recordText("https://github.com/anthropics/claude-code")
        clip.recordText("#1F4E79")
        clip.recordText("const palette = {\n  ink: \"#1F4E79\",\n  ochre: \"#C8963E\",\n};")
        clip.togglePin(clip.items[2].id)
        try snap("20-clipboard", ClipboardPanel(store: clip).padding(12).background(.black),
                 size: CGSize(width: 620, height: 170), wait: 0.4)
    }

    /// Khung hình ambient light quét qua thông báo (nhắc nghỉ, đổi bài).
    func testHUDSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        out = dir
        let rec = NotificationRecord(id: 1, bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                     title: "New message in ai1st-silk-team", subtitle: "",
                                     body: "Tung: em ơi trong tuần bọn anh còn việc", date: Date())
        for pill in [false, true] {
            let (vm, _) = makeVM(media: false)
            vm.pillMode = pill
            if pill { vm.coreWidth = 22 }
            vm.hudNotification = rec
            try snap(pill ? "hud-pill" : "hud-notch", NotchRootView(vm: vm), wait: 1.0)
        }
    }

    func testAmbientSweepFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        for (label, setup) in [("break", { (vm: NotchViewModel) in vm.showBreak() }),
                               ("track", { (vm: NotchViewModel) in vm.titleReveal = true })] as [(String, (NotchViewModel) -> Void)] {
            let (vm, _) = makeVM(media: true)
            let size = CGSize(width: 520, height: 120)
            let host = NSHostingView(rootView: NotchRootView(vm: vm).frame(width: size.width, height: size.height)
                .background(Color(white: 0.85)))
            let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                             backing: .buffered, defer: false)
            w.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            setup(vm)
            for (i, t) in [0.35, 0.65, 0.95, 1.6].enumerated() {
                RunLoop.main.run(until: Date().addingTimeInterval(i == 0 ? t : t - [0.35, 0.65, 0.95, 1.6][i - 1]))
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "\(dir)/sweep-\(label)-\(i).png"))
            }
        }
    }

    /// Đo bề rộng notch từng khung khi thu vào (hover → thôi hover, mở → đóng):
    /// không khung nào được nhỏ hơn kích thước cuối (không co lố nhỏ hơn camera).
    func testCollapseNoOvershoot() throws {
        let (vm, _) = makeVM(media: true)
        let size = CGSize(width: 700, height: 300)
        let host = NSHostingView(rootView: NotchRootView(vm: vm).frame(width: size.width, height: size.height)
            .background(Color.white))
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.contentView = host
        func blackWidth() -> Int {
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let y = 6   // hàng điểm ảnh sát mép trên
            var n = 0
            for x in 0..<rep.pixelsWide { if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.2 { n += 1 } }
            return n
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rest = blackWidth()
        for (label, on, off) in [("hover", { vm.hovering = true }, { vm.hovering = false }),
                                 ("expand", { vm.expanded = true }, { vm.collapse() })] as [(String, () -> Void, () -> Void)] {
            on(); RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            off()
            var minW = Int.max
            var trace: [Int] = []
            for i in 0..<40 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.016)); let b = blackWidth(); trace.append(b); minW = min(minW, b)
                if let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"], [0, 6, 30].contains(i) {
                    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/col-\(label)-\(i).png"))
                }
            }
            print("STATE \(label): reveal=\(vm.leftReveal)/\(vm.rightReveal) core=\(vm.coreWidth) h=\(vm.compactHeight) state=\(vm.compactState) bulge=\(String(describing: vm.bulge))")
            print("TRACE \(label):", trace)
            // So với kích thước SAU KHI DỪNG (trạng thái cuối có thể khác lúc đầu, vd tên bài đã ẩn).
            let settled = trace.last ?? rest
            print("COLLAPSE \(label): start=\(rest) settled=\(settled) min=\(minW)")
            XCTAssertGreaterThanOrEqual(minW, settled - 2, "\(label): co lố nhỏ hơn kích thước cuối")
        }
    }

    /// Ghi khung hình hiệu ứng chuyển màn (thu → nở) để QC.
    func testHopFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        let (vm, _) = makeVM(media: true)
        // Bắt đầu ở dạng notch, chuyển sang pill (ca khó nhất).
        let size = CGSize(width: 400, height: 60)
        let host = NSHostingView(rootView: NotchRootView(vm: vm).frame(width: size.width, height: size.height)
            .background(Color(white: 0.9)))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        var frames: [NSBitmapImageRep] = []
        func grab() {
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep); frames.append(rep)
        }
        withAnimation(.easeInOut(duration: 0.26)) { vm.screenHopHidden = true }
        for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.033)); grab() }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { vm.pillMode = true; vm.notchHeight = 30; vm.coreWidth = 22 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.42)) { vm.screenHopHidden = false }
        for _ in 0..<16 { RunLoop.main.run(until: Date().addingTimeInterval(0.033)); grab() }
        for (i, f) in frames.enumerated() {
            try f.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(dir)/hop-\(String(format: "%02d", i)).png"))
        }
    }

    /// Mỗi tab ở trạng thái mở rộng — để rà UI toàn app.
    func testTabSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        out = dir
        for tab in RailTab.allCases {
            let (vm, _) = makeVM(media: true)
            vm.expanded = true
            vm.clipTabActive = tab == .clipboard; vm.timerTabActive = tab == .timer; vm.musicTabActive = tab == .music
            vm.calTabActive = tab == .calendar
            vm.notifTabActive = tab == .notifications
            vm.panelWantsTall = [.calendar, .settings, .learn].contains(tab)
            if tab == .timer { AppSettings.shared.timerPage = 1 }
            try snap("tab-\(tab.rawValue)", NotchRootView(vm: vm, initialTab: tab),
                     size: CGSize(width: 700, height: 380), wait: 1.2)
        }
        // Tab Timer: đủ 3 chế độ (cột trái chọn chế độ).
        for page in 0..<3 {
            let (vm, _) = makeVM(media: true)
            vm.expanded = true; vm.timerTabActive = true
            AppSettings.shared.timerPage = page
            try snap("timer-page\(page)", NotchRootView(vm: vm, initialTab: .timer),
                     size: CGSize(width: 700, height: 300), wait: 1.0)
        }
        do {   // Nhịp đang chạy: Pomodoro, đã qua chặng đầu.
            let (vm, _) = makeVM(media: true)
            vm.expanded = true; vm.timerTabActive = true
            AppSettings.shared.timerPage = 1
            let cfg = AppSettings.shared.pomodoroConfig
            vm.timerSequence.startSequence(flatten(.pomodoro(cfg, sound: "Glass")), label: "Pomodoro")
            vm.timerSequence.skip()
            try snap("timer-flow-running", NotchRootView(vm: vm, initialTab: .timer),
                     size: CGSize(width: 700, height: 300), wait: 1.5)
            vm.timerSequence.reset()
        }
        for f in LauncherFeature.allCases {   // Tab Tiện ích: từng tính năng.
            let (vm, _) = makeVM(media: true)
            vm.expanded = true; vm.toolsTabActive = true
            UserDefaults.standard.set(f.rawValue, forKey: "cfg.toolsPage")
            try snap("tools-\(f.rawValue)", NotchRootView(vm: vm, initialTab: .tools),
                     size: CGSize(width: 700, height: 320), wait: 1.0)
        }
        do {   // Notch theo thời tiết (dữ liệu thật/cache của WeatherStore).
            WeatherStore.shared.start()
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            AppSettings.shared.weatherAmbient = true
            let (vm, _) = makeVM(media: true)
            vm.expanded = true; vm.timerTabActive = true
            try snap("weather-ambient", NotchRootView(vm: vm, initialTab: .timer),
                     size: CGSize(width: 700, height: 300), wait: 1.0)
            AppSettings.shared.weatherAmbient = false
        }
        do {   // Giao diện sáng (kính): mọi tab + pill.
            AppSettings.shared.appearanceMode = "light"
            for tab in RailTab.allCases {
                let (vm, _) = makeVM(media: true)
                vm.expanded = true
                vm.clipTabActive = tab == .clipboard; vm.timerTabActive = tab == .timer; vm.musicTabActive = tab == .music
                vm.calTabActive = tab == .calendar; vm.notifTabActive = tab == .notifications
                vm.toolsTabActive = tab == .tools
                vm.panelWantsTall = [.calendar, .settings, .learn].contains(tab)
                try snap("light-\(tab.rawValue)", NotchRootView(vm: vm, initialTab: tab),
                         size: CGSize(width: 700, height: 380), wait: 1.2)
            }
            let (pv, _) = makeVM(media: true)
            pv.pillMode = true; pv.notchHeight = 30; pv.coreWidth = 82; pv.expanded = true; pv.timerTabActive = true
            try snap("light-pill", NotchRootView(vm: pv, initialTab: .timer), size: CGSize(width: 700, height: 300), wait: 1.0)
            AppSettings.shared.appearanceMode = "dark"
        }
        // Pill (màn hình không notch): thu gọn + mở.
        var (pv, _) = makeVM(media: true)
        pv.pillMode = true; pv.notchHeight = 30; pv.coreWidth = 82
        try snap("pill-compact", NotchRootView(vm: pv), size: CGSize(width: 700, height: 120), wait: 0.6)
        pv.titleReveal = false
        try snap("pill-resting", NotchRootView(vm: pv), size: CGSize(width: 700, height: 120), wait: 0.6)
        (pv, _) = makeVM(media: true)
        pv.pillMode = true; pv.notchHeight = 30; pv.expanded = true; pv.notifTabActive = true
        try snap("pill-expanded", NotchRootView(vm: pv, initialTab: .notifications), size: CGSize(width: 700, height: 260), wait: 1.0)
    }
}

/// Render từng khung hoạt ảnh ra PNG rồi ghép video bằng ffmpeg — chỉ khi NOTCH_VIDEO=<dir>.
@MainActor
final class SpriteVideoCheck: XCTestCase {
    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    func testRenderLogo() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_VIDEO"] else { throw XCTSkip("no NOTCH_VIDEO") }
        let sub = URL(fileURLWithPath: dir).appendingPathComponent("logo")
        try? FileManager.default.removeItem(at: sub)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let n = ClaudeSpark.keyframes.count * ClaudeSpark.framesPerMorph * 2
        for i in 0..<n {
            let t = Double(i) / ClaudeSpark.fps
            let p = ClaudeSpark.pose(at: t)
            let view = VStack(spacing: 22) {
                ClaudeSparkCanvas(shape: p.shape, angle: p.angle, size: 180, twinkle: ClaudeSpark.twinkle(at: t))
                Text("logo Claude biến hình · 8 khung/giây").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            try render(view, size: CGSize(width: 720, height: 480), to: sub.appendingPathComponent(String(format: "%03d.png", i)))
        }
    }

    func testRenderFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_VIDEO"] else { throw XCTSkip("no NOTCH_VIDEO") }
        let fm = FileManager.default
        for (name, frames, palette, px, label) in [
            ("cat", (0..<PixelCat.loop.count * 2).map(PixelCat.frame), PixelCat.palette, CGFloat(12), "Đứng dậy nào · uống ngụm nước"),
            ("clawd", Clawd.timeline(.work) + Clawd.timeline(.work)
                      + Clawd.timeline(.alert) + Clawd.timeline(.alert) + Clawd.timeline(.alert)
                      + Clawd.timeline(.happy) + Clawd.timeline(.happy),
             Clawd.palette, CGFloat(14), "gõ phím + suy nghĩ (đang làm) → vẫy tay (chờ duyệt) → nhảy mừng (xong)"),
        ] {
            let sub = URL(fileURLWithPath: dir).appendingPathComponent(name)
            try? fm.removeItem(at: sub)
            try fm.createDirectory(at: sub, withIntermediateDirectories: true)
            for (i, f) in frames.enumerated() {
                let w = CGFloat(f[0].count) * px, h = CGFloat(f.count) * px
                let view = VStack(spacing: 22) {
                    PixelCanvas(frame: f, pixel: px, palette: palette).frame(width: w, height: h)
                    Text(label).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                try render(view, size: CGSize(width: 720, height: 480),
                           to: sub.appendingPathComponent(String(format: "%03d.png", i)))
            }
        }
    }
}

private struct PixelSheetCell: View {
    let frame: [String]
    var body: some View {
        Canvas { ctx, _ in
            let px: CGFloat = 4.5
            for (y, row) in frame.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = PixelCat.palette[ch] else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(c))
                }
            }
        }
        .frame(width: 140, height: 140)
    }
}

/// Màn "Chọn nghĩa" với từ dài ở bề ngang popup thật (400 − 2×22) — soát xuống dòng.
@MainActor
final class LearnPracticeSnapshotCheck: XCTestCase {
    func testLongHeadword() throws {
        guard let out = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        let w = LearnWord(headword: "overestimate", pos: "verb", ipaUK: "/ˌəʊ.vərˈes.tɪ.meɪt/", ipaUS: "/ˌoʊ.vɚˈes.tə.meɪt/",
                          senses: [LearnSense(guideword: "TOO HIGH", level: "C1", defEN: "to think something is bigger than it is",
                                              defVI: "đánh giá quá cao", examples: [])])
        let q = PracticeQuestion(key: SenseKey(wordID: "overestimate", index: 0), mode: .mcqWord,
                                 options: ["đánh giá quá cao", "đại tu, cải tổ", "làm đau, bị thương", "giới hạn"],
                                 correct: 0, answer: "đánh giá quá cao")
        let view = PracticeQuestionView(q: q, word: w, sense: w.senses[0], stateBefore: nil, compact: true,
                                        onAnswer: { _ in }, onNext: {}, onKnown: {})
            .environment(\.learnOnNotch, true).foregroundStyle(.white)
            .frame(width: 356, height: 220).background(.black)
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 220), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/learn-long.png"))
    }
}

@MainActor
final class CodexVisualCheck: XCTestCase {
    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    func testRenderKnot() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_VIDEO"] else { throw XCTSkip("no NOTCH_VIDEO") }
        let sub = URL(fileURLWithPath: dir).appendingPathComponent("knot")
        try? FileManager.default.removeItem(at: sub)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let n = OpenAIKnot.keyframes.count * OpenAIKnot.framesPerMorph * 2
        for i in 0..<n {
            let p = OpenAIKnot.pose(at: Double(i) / OpenAIKnot.fps)
            let view = VStack(spacing: 22) {
                OpenAIKnotCanvas(shape: p.shape, angle: p.angle, size: 200)
                Text("Codex · logo biến hình").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            try render(view, size: CGSize(width: 720, height: 480), to: sub.appendingPathComponent(String(format: "%03d.png", i)))
        }
    }
}


@MainActor
final class AgentBadgeTests: XCTestCase {
    func testOneBadgePerAgentWithCountAndWaiting() {
        let vm = NotchViewModel(media: NotchSnapshotCheck.FakeMedia(), notifier: NotchSnapshotCheck.FakeNotifier())
        let now = Date()
        let c1 = ClaudeSession(id: "c1", cwd: "/r/a", state: .working, updatedAt: now)
        let c2 = ClaudeSession(id: "c2", cwd: "/r/b", state: .working, updatedAt: now)
        let x1 = ClaudeSession(id: "codex:x1", agent: .codex, cwd: "/r/c", state: .waiting, updatedAt: now)
        let done = ClaudeSession(id: "c3", cwd: "/r/d", state: .done, updatedAt: now)
        vm._previewClaude(sessions: [x1, c1, c2, done])
        let b = vm.claudeBadges
        XCTAssertEqual(b.map(\.agent), [.claude, .codex])      // thứ tự cố định
        XCTAssertEqual(b[0].count, 2)                             // phiên "done" không tính
        XCTAssertFalse(b[0].waiting)
        XCTAssertTrue(b[1].waiting)
        vm._previewClaude(sessions: [done])
        XCTAssertTrue(vm.claudeBadges.isEmpty)
    }

}

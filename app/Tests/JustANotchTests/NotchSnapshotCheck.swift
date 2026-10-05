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

        // 8. Sprite phóng to từng khung để soát pixel art.
        let frames = [0, 11, 18, 30, 34].map(PixelCat.frame)
        let sheet = HStack(spacing: 24) {
            ForEach(0..<frames.count, id: \.self) { i in
                PixelSheetCell(frame: frames[i])
            }
        }.padding(20).background(.black)
        try snap("8-sprite", sheet, size: CGSize(width: 820, height: 200), wait: 0.3)
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
                                        onAnswer: { _ in }, onNext: {}, onSkip: {}, onKnown: {})
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

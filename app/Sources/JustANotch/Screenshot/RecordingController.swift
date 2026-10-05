import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Quay màn hình kiểu CleanShot: ⌘⇧6 → chọn vùng / cửa sổ / cả màn hình → quay
/// (viền đứt nét quanh vùng + thanh điều khiển nổi) → ⌘⇧6 hoặc ■ để dừng →
/// thumbnail video ở góc (sao chép file / lưu / mở / kéo-thả).
@MainActor
final class RecordingController: ObservableObject {
    static let shared = RecordingController()

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt = Date()

    private var recorder: ScreenRecorder?
    private var session: SelectionSession?
    private var border: NSPanel?
    private var controls: NSPanel?
    private var screen: NSScreen?
    private var selecting = false

    /// Phím tắt: đang quay → dừng; chưa → bắt đầu chọn vùng.
    func toggle() {
        if isRecording { stop() } else { Task { await select() } }
    }

    // MARK: Chọn vùng

    private func select() async {
        let shots = ScreenshotController.shared
        guard shots.ensurePermission(), !selecting, session == nil else { return }
        selecting = true
        defer { selecting = false }
        var frozen: [SelectionSession.Frozen] = []
        for s in NSScreen.screens {
            if let img = try? await ScreenGrabber.captureDisplay(s) { frozen.append(.init(screen: s, image: img)) }
        }
        guard !frozen.isEmpty else { NSSound.beep(); return }
        session = SelectionSession(frozen: frozen, windowMode: false, verb: "quay") { [weak self] result in
            guard let self else { return }
            self.session = nil
            guard let (f, pick) = result else { return }
            Task { await self.begin(on: f.screen, pick: pick) }
        }
    }

    // MARK: Quay

    private func begin(on screen: NSScreen, pick: SelectionSession.Pick) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            NSSound.beep(); return
        }
        let scale = screen.backingScaleFactor
        let id = ScreenGrabber.displayID(screen)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { NSSound.beep(); return }

        let filter: SCContentFilter
        var pixel: CGSize
        var source: CGRect?
        var frame: CGRect?          // khung vùng quay (cục bộ màn hình, gốc trên-trái) để vẽ viền
        switch pick {
        case .full:
            filter = ScreenGrabber.displayFilter(display, content: content)
            pixel = CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale)
        case .area(let r):
            filter = ScreenGrabber.displayFilter(display, content: content)
            pixel = CGSize(width: r.width * scale, height: r.height * scale)
            source = r
            frame = r
        case .window(let wid, let r):
            if let w = content.windows.first(where: { $0.windowID == wid }) {
                filter = SCContentFilter(desktopIndependentWindow: w)
                pixel = CGSize(width: w.frame.width * scale, height: w.frame.height * scale)
            } else {
                filter = ScreenGrabber.displayFilter(display, content: content)
                pixel = CGSize(width: r.width * scale, height: r.height * scale)
                source = r
            }
            frame = r
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("JustANotchShots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rec = ScreenRecorder(url: dir.appendingPathComponent(ScreenshotController.videoName(Date())))
        do {
            try await rec.start(filter: filter, pixelSize: pixel, sourceRect: source,
                                audio: AppSettings.shared.recordAudio)
        } catch {
            NSSound.beep(); return
        }
        recorder = rec
        self.screen = screen
        startedAt = Date()
        isRecording = true
        showChrome(frame: frame, on: screen)
    }

    func stop() {
        guard let rec = recorder else { return }
        recorder = nil
        isRecording = false
        hideChrome()
        Task {
            let dur = rec.duration
            guard await rec.stop() else { NSSound.beep(); return }
            ScreenshotController.playShutter()
            await deliver(rec.url, duration: dur)
        }
    }

    func cancel() {
        guard let rec = recorder else { return }
        recorder = nil
        isRecording = false
        hideChrome()
        Task { await rec.cancel() }
    }

    private func deliver(_ url: URL, duration: Double) async {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 800, height: 800)
        guard let thumb = try? await gen.image(at: CMTime(seconds: min(0.3, duration / 2), preferredTimescale: 600)).image
        else { return }
        let shot = Shot(image: thumb, scale: 2, png: Data(), tempURL: url, video: url, duration: duration)
        if AppSettings.shared.shotAutoSave { ScreenshotController.shared.save(shot) }
        QuickAccess.shared.show(shot, on: screen ?? ScreenshotController.screenUnderMouse)
    }

    // MARK: Viền + thanh điều khiển

    private func showChrome(frame: CGRect?, on screen: NSScreen) {
        // Đổi khung cục bộ (gốc trên-trái) → toạ độ AppKit toàn cục.
        func global(_ r: CGRect) -> CGRect {
            CGRect(x: screen.frame.minX + r.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        if let f = frame {
            // Phủ cả màn hình: tối nhẹ bên ngoài + khung ngắm quanh vùng quay (bấm xuyên qua).
            let p = Self.panel(screen.frame, level: .statusBar)
            p.ignoresMouseEvents = true
            p.contentView = NSHostingView(rootView: RecordingFrame(rect: f, size: screen.frame.size))
            p.orderFrontRegardless()
            border = p
        }
        // Thanh điều khiển: dưới vùng quay (hoặc trên nếu sát đáy), luôn trong màn hình.
        let size = CGSize(width: 214, height: 44)
        let vf = screen.visibleFrame
        var origin: CGPoint
        if let f = frame {
            let g = global(f)
            origin = CGPoint(x: g.midX - size.width / 2, y: g.minY - size.height - 14)
            if origin.y < vf.minY + 8 { origin.y = g.maxY + 14 }
            if origin.y + size.height > vf.maxY { origin.y = vf.minY + 24 }
        } else {
            origin = CGPoint(x: vf.midX - size.width / 2, y: vf.minY + 24)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        let c = Self.panel(CGRect(origin: origin, size: size), level: .statusBar)
        c.contentView = NSHostingView(rootView: RecordingControls(model: self))
        c.orderFrontRegardless()
        controls = c
    }

    private func hideChrome() {
        border?.orderOut(nil); border = nil
        controls?.orderOut(nil); controls = nil
    }

    private static func panel(_ frame: CGRect, level: NSWindow.Level) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = level
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

/// Khung ngắm vùng đang quay: ngoài vùng tối nhẹ, viền trắng mảnh có quầng mờ,
/// 4 góc ngoặc vuông. Hiện ra bằng một nhịp mờ dần (không nhấp nháy liên tục).
struct RecordingFrame: View {
    let rect: CGRect      // cục bộ màn hình, gốc trên-trái
    let size: CGSize
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
            }
            .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                .shadow(color: .white.opacity(0.35), radius: 6)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            Brackets()
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.35), radius: 3)
                .frame(width: rect.width + 6, height: rect.height + 6)
                .offset(x: rect.minX - 3, y: rect.minY - 3)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { shown = true } }
    }
}

/// 4 góc ngoặc vuông của khung ngắm.
private struct Brackets: Shape {
    func path(in r: CGRect) -> Path {
        let l = min(18, r.width / 4, r.height / 4)
        var p = Path()
        for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                            (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: c.x, y: c.y + dy * l))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x + dx * l, y: c.y))
        }
        return p
    }
}

/// ● 00:12   ■ Dừng   ✕
private struct RecordingControls: View {
    @ObservedObject var model: RecordingController
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(red: 1, green: 0.27, blue: 0.27)).frame(width: 9, height: 9)
                .opacity(pulse ? 0.35 : 1)
                .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.clock(ctx.date.timeIntervalSince(model.startedAt)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 50, alignment: .leading)
            Button { model.stop() } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                    Text("Dừng").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(Color(red: 1, green: 0.27, blue: 0.27)))
            }
            .buttonStyle(.plain).help("Dừng quay (⌘⇧6)")
            Button { model.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain).help("Huỷ bản ghi")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color(white: 0.08).opacity(0.94)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

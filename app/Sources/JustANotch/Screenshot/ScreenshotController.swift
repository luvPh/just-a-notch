import AppKit
import SwiftUI

/// Một ảnh vừa chụp.
struct Shot: Identifiable, Equatable {
    let id = UUID()
    let image: CGImage
    let scale: CGFloat
    let date = Date()
    let png: Data
    /// File tạm (dùng để kéo-thả sang app khác). Với video: chính file .mp4.
    let tempURL: URL
    /// Bản ghi màn hình: đường dẫn video + thời lượng (giây). nil = ảnh chụp.
    var video: URL? = nil
    var duration: Double = 0

    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
    var nsImage: NSImage { NSImage(cgImage: image, size: pointSize) }

    static func == (a: Shot, b: Shot) -> Bool { a.id == b.id }
}

/// Điều phối chụp màn hình kiểu CleanShot: đóng băng → chọn → ảnh → clipboard +
/// thumbnail nổi (sao chép / lưu / chú thích / ghim / kéo-thả).
@MainActor
final class ScreenshotController {
    static let shared = ScreenshotController()

    /// Ảnh chụp được treo thẳng vào tab Clipboard.
    var clipboard: ClipboardStore?

    private var session: SelectionSession?
    private var busy = false
    private let settings = AppSettings.shared

    // MARK: Lệnh

    func captureArea() { Task { await select(windowMode: false) } }
    func captureWindow() { Task { await select(windowMode: true) } }

    func captureFullScreen() {
        Task {
            guard ensurePermission(), !busy else { return }
            let screen = Self.screenUnderMouse
            guard let cg = try? await ScreenGrabber.captureDisplay(screen) else { return failed() }
            deliver(cg, scale: screen.backingScaleFactor, on: screen)
        }
    }

    // MARK: Luồng chọn

    private func select(windowMode: Bool) async {
        guard ensurePermission(), !busy, session == nil else { return }
        busy = true
        defer { busy = false }
        var frozen: [SelectionSession.Frozen] = []
        for s in NSScreen.screens {
            if let img = try? await ScreenGrabber.captureDisplay(s) { frozen.append(.init(screen: s, image: img)) }
        }
        guard !frozen.isEmpty else { return failed() }
        session = SelectionSession(frozen: frozen, windowMode: windowMode) { [weak self] result in
            guard let self else { return }
            self.session = nil
            guard let (f, pick) = result else { return }
            Task { await self.resolve(f, pick) }
        }
    }

    private func resolve(_ f: SelectionSession.Frozen, _ pick: SelectionSession.Pick) async {
        let scale = CGFloat(f.image.width) / f.screen.frame.width
        switch pick {
        case .full:
            deliver(f.image, scale: scale, on: f.screen)
        case .area(let r):
            let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
            if let cg = f.image.cropping(to: px) { deliver(cg, scale: scale, on: f.screen) }
        case .window(let id, let r):
            // Chụp riêng cửa sổ (trong suốt, có bóng) — lỗi thì cắt từ ảnh đóng băng.
            if let cg = try? await ScreenGrabber.captureWindow(id: id, scale: scale, shadow: settings.shotWindowShadow) {
                deliver(cg, scale: scale, on: f.screen)
            } else {
                let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
                if let cg = f.image.cropping(to: px) { deliver(cg, scale: scale, on: f.screen) }
            }
        }
    }

    // MARK: Kết quả

    private func deliver(_ cg: CGImage, scale: CGFloat, on screen: NSScreen) {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = CGSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)   // 144 dpi cho Retina
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("JustANotchShots", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent(Self.fileName(Date()))
        try? png.write(to: url)
        let shot = Shot(image: cg, scale: scale, png: png, tempURL: url)

        Self.playShutter()
        clipboard?.addScreenshot(png: png, copy: settings.shotAutoCopy)
        if settings.shotAutoSave { _ = save(shot) }
        QuickAccess.shared.show(shot, on: screen)
    }

    /// Lưu vào thư mục đã chọn. Trả về URL đã lưu.
    @discardableResult
    func save(_ shot: Shot) -> URL? {
        let dir = URL(fileURLWithPath: settings.shotFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let video = shot.video != nil
        func name(_ s: String) -> String { video ? Self.videoName(shot.date, suffix: s) : Self.fileName(shot.date, suffix: s) }
        var url = dir.appendingPathComponent(name(""))
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent(name(" (\(n))")); n += 1 }
        do {
            if let v = shot.video { try FileManager.default.copyItem(at: v, to: url) } else { try shot.png.write(to: url) }
            return url
        } catch { return nil }
    }

    func copy(_ shot: Shot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let v = shot.video { pb.writeObjects([v as NSURL]); return }
        pb.setData(shot.png, forType: .png)
        if let tiff = shot.nsImage.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// Ảnh đã chỉnh trong trình chú thích → coi như một lần chụp mới (clipboard + thumbnail).
    func deliverEdited(_ cg: CGImage, scale: CGFloat) {
        deliver(cg, scale: scale, on: Self.screenUnderMouse)
    }

    // MARK: Tiện ích

    static var screenUnderMouse: NSScreen {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func videoName(_ d: Date, suffix: String = "") -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'lúc' HH.mm.ss"
        return "Bản ghi màn hình \(f.string(from: d))\(suffix).mp4"
    }

    static func fileName(_ d: Date, suffix: String = "") -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'lúc' HH.mm.ss"
        return "Ảnh chụp màn hình \(f.string(from: d))\(suffix).png"
    }

    static func playShutter() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }

    private func failed() { NSSound.beep() }

    /// Chưa có quyền Screen Recording → hỏi quyền + hướng dẫn (chỉ hỏi, không chặn app).
    func ensurePermission() -> Bool {
        if ScreenGrabber.hasPermission { return true }
        ScreenGrabber.requestPermission()
        let a = NSAlert()
        a.messageText = "Cần quyền Ghi màn hình"
        a.informativeText = "Để chụp màn hình, hãy bật Just a Notch trong System Settings → Privacy & Security → Screen & System Audio Recording, rồi thử lại."
        a.addButton(withTitle: "Mở System Settings")
        a.addButton(withTitle: "Để sau")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}

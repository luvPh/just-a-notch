import AppKit
import ScreenCaptureKit

/// Chụp ảnh màn hình / cửa sổ bằng ScreenCaptureKit (macOS 14+).
/// Cần quyền Screen Recording. Ảnh trả về ở độ phân giải pixel thật.
@MainActor
enum ScreenGrabber {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Hỏi quyền (macOS hiện hộp thoại / mở System Settings ở lần đầu).
    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Cửa sổ của chính app VẪN được chụp (notch). Các cửa sổ khác của app (thumbnail,
    /// overlay chọn vùng, khung quay…) bị loại. Controller đăng ký id cửa sổ notch ở đây.
    /// Đọc lúc chụp (cửa sổ chỉ có số hiệu sau khi đã hiện lên màn hình).
    static var keptOwnWindows: () -> Set<CGWindowID> = { [] }

    /// Bộ lọc màn hình: mọi thứ + notch, trừ các cửa sổ phụ của app.
    static func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let keep = keptOwnWindows()
        let mine = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier && !keep.contains($0.windowID)
        }
        return SCContentFilter(display: display, excludingWindows: mine)
    }

    /// Toàn bộ một màn hình (kể cả notch), không gồm các cửa sổ phụ của app.
    static func captureDisplay(_ screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = displayID(screen)
        guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
            throw NSError(domain: "ScreenGrabber", code: 1)
        }
        let filter = displayFilter(display, content: content)
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = false
        cfg.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Một cửa sổ riêng lẻ (nền trong suốt, có/không bóng đổ).
    static func captureWindow(id: CGWindowID, scale: CGFloat, shadow: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let w = content.windows.first(where: { $0.windowID == id }) else {
            throw NSError(domain: "ScreenGrabber", code: 2)
        }
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let cfg = SCStreamConfiguration()
        cfg.width = Int(w.frame.width * scale)
        cfg.height = Int(w.frame.height * scale)
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = !shadow
        cfg.shouldBeOpaque = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Cửa sổ đang hiện trên màn hình, TỪ TRƯỚC RA SAU, toạ độ toàn cục gốc trên-trái
    /// (Quartz). Bỏ cửa sổ của app mình, thanh menu/Dock, cửa sổ quá nhỏ.
    struct WindowInfo { let id: CGWindowID; let frame: CGRect; let owner: String }

    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  (d[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.width > 40, r.height > 40,
                  (d[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0.01
            else { return nil }
            return WindowInfo(id: id, frame: r, owner: d[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// Chiều cao màn hình chính — để đổi toạ độ Quartz (gốc trên-trái) ↔ AppKit (gốc dưới-trái).
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Khung `screen` trong toạ độ Quartz toàn cục.
    static func quartzFrame(of screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
               width: screen.frame.width, height: screen.frame.height)
    }
}

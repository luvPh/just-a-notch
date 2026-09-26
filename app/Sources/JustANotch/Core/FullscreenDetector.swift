// app/Sources/JustANotch/Core/FullscreenDetector.swift
import AppKit
import CoreGraphics

/// Phát hiện app phía trước đang full màn hình (phim, game, trình chiếu, họp…)
/// để popup Learn bỏ qua lượt. Chỉ đọc kích thước cửa sổ — không cần quyền ghi màn hình.
enum FullscreenDetector {
    static func isFrontAppFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { return false }
            return screens.contains { abs($0.width - width) < 1 && abs($0.height - height) < 1 }
        }
    }
}

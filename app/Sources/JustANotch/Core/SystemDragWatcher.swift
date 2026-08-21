import AppKit

/// Phát hiện có cú kéo FILE đang diễn ra ở bất kỳ đâu trên hệ thống, để notch tự
/// bung kệ tạm làm đích thả — không phải hover lên notch trước.
///
/// Cách nhận biết (kiểu Dropover/Yoink, không cần quyền gì thêm): mỗi khi một
/// phiên kéo bắt đầu, hệ thống ghi dữ liệu lên pasteboard `.drag` ⇒ `changeCount`
/// tăng. Kết hợp với "nút chuột đang giữ" để biết cú kéo còn hay đã kết thúc.
/// Global mouse monitor không dùng được ở đây vì trong vòng lặp kéo của hệ thống,
/// event chuột không đến được app khác — nên poll nhẹ là cách đáng tin cậy.
@MainActor
final class SystemDragWatcher {
    private let pasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount: Int
    private var dragging = false
    private var timer: Timer?

    private let onBegan: () -> Void
    private let onEnded: () -> Void

    /// Nhịp poll: đủ nhanh để kệ hiện gần như ngay khi nhấc file, đủ thưa để
    /// không đáng kể về CPU (chỉ đọc `changeCount` + trạng thái nút chuột).
    private let interval: TimeInterval = 0.15

    init(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
        self.onBegan = onBegan
        self.onEnded = onEnded
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func tick() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        if dragging {
            // Nhả chuột ⇒ phiên kéo kết thúc (dù đã thả vào đâu hay huỷ).
            if !mouseDown {
                dragging = false
                onEnded()
            }
            return
        }

        let cc = pasteboard.changeCount
        guard cc != lastChangeCount else { return }
        lastChangeCount = cc
        // Chỉ quan tâm kéo file (bỏ qua kéo text/ảnh trong app khác).
        guard mouseDown, hasFileURL else { return }
        dragging = true
        onBegan()
    }

    private var hasFileURL: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self],
                                 options: [.urlReadingFileURLsOnly: true])
    }
}

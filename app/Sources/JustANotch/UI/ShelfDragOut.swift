import SwiftUI
import AppKit

/// Lớp phủ trong suốt biến một tile trên shelf thành nguồn kéo AppKit thật.
///
/// SwiftUI `.onDrag` không cho biết cú kéo kết thúc thế nào, nên không thể xoá
/// mục sau khi kéo ra. `NSDraggingSource` thì có: `endedAt:operation:` cho biết
/// đã có nơi nhận file hay người dùng huỷ giữa đường.
struct ShelfDragOut: NSViewRepresentable {
    /// File thật (bản copy trong temp của phiên) sẽ được kéo ra.
    let url: URL
    /// Ảnh kéo theo con trỏ.
    let icon: NSImage
    /// `true` khi có nơi nhận file ⇒ mục nên rời shelf. `false` khi huỷ.
    let onEnd: (Bool) -> Void
    /// Góc trên-phải chừa lại cho nút ✕ của SwiftUI (không nhận chuột ở đây).
    var excludeTopTrailing = CGSize(width: 24, height: 24)

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.apply(url: url, icon: icon, onEnd: onEnd, exclude: excludeTopTrailing)
        return v
    }

    func updateNSView(_ v: DragSourceView, context: Context) {
        v.apply(url: url, icon: icon, onEnd: onEnd, exclude: excludeTopTrailing)
    }

    final class DragSourceView: NSView, NSDraggingSource {
        private var url: URL?
        private var icon: NSImage?
        private var onEnd: ((Bool) -> Void)?
        private var exclude: CGSize = .zero
        private var dragging = false

        func apply(url: URL, icon: NSImage, onEnd: @escaping (Bool) -> Void, exclude: CGSize) {
            self.url = url
            self.icon = icon
            self.onEnd = onEnd
            self.exclude = exclude
        }

        /// Nhường góc trên-phải cho nút ✕ nằm dưới (theo z-order của SwiftUI).
        override func hitTest(_ point: NSPoint) -> NSView? {
            let p = convert(point, from: superview)
            guard bounds.contains(p) else { return nil }
            if p.x > bounds.maxX - exclude.width, p.y > bounds.maxY - exclude.height { return nil }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { /* chờ xem có kéo không */ }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let url, let icon else { return }
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let side: CGFloat = 48
            let origin = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: origin.x - side / 2, y: origin.y - side / 2,
                                        width: side, height: side),
                                 contents: icon)
            dragging = true
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .move, .generic, .link]
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            dragging = false
            onEnd?(operation != [])
        }
    }
}

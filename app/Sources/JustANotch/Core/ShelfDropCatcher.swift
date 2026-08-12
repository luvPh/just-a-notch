import AppKit
import UniformTypeIdentifiers

/// Panel nhỏ, luôn nhận sự kiện, đặt phủ lên LÕI notch. Nhiệm vụ duy nhất: phát
/// hiện khi có drag file tới notch đang đóng để bung shelf — vì panel chính lúc
/// đóng đang `ignoresMouseEvents` nên không tự nhận được drag/drop từ Finder.
///
/// - Kéo file vào vùng lõi → `onDragEnter` (bung shelf).
/// - Thả ngay trên lõi → `onDrop` (thêm file).
/// - Bấm chuột lên lõi → `onClick` (mở notch như bấm island).
@MainActor
final class ShelfDropCatcher {
    private let panel: NSPanel
    private let view: DraggingView

    init(onDragEnter: @escaping () -> Void,
         onDrop: @escaping ([URL]) -> Void,
         onClick: @escaping () -> Void) {
        view = DraggingView()
        view.onDragEnter = onDragEnter
        view.onDropURLs = onDrop
        view.onClick = onClick
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Trên panel chính (statusBar) để bắt drag trước.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func setFrame(_ rect: CGRect) { panel.setFrame(rect, display: true) }
    func orderFront() { panel.orderFrontRegardless() }

    /// NSView đích của drag: chỉ quan tâm file URL.
    final class DraggingView: NSView {
        var onDragEnter: (() -> Void)?
        var onDropURLs: (([URL]) -> Void)?
        var onClick: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }
        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onDragEnter?()
            return .copy
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
            guard !urls.isEmpty else { return false }
            onDropURLs?(urls)
            return true
        }

        override func mouseDown(with event: NSEvent) { onClick?() }
    }
}

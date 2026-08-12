import AppKit
import SwiftUI
import Combine

/// Panel nổi có thể nhận phím (cho Esc để đóng). Khác NotchPanel: luôn
/// canBecomeKey và tự đóng khi bấm Esc.
private final class FilesPopupPanel: NSPanel {
    var onCancel: (() -> Void)?
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)   // trên cả notch
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }   // Esc
}

/// Bật/tắt (⌥⇧N) một popup nổi hiển thị tab Files ở dạng mở rộng, canh GIỮA màn
/// hình đang có con trỏ. Đóng khi: Esc, bấm ra ngoài, hoặc bấm lại phím tắt.
@MainActor
final class FilesPopupController {
    private let store: FileShortcutStore
    private var panel: FilesPopupPanel?
    private var outsideMonitor: Any?

    private let size = CGSize(width: 640, height: 460)

    init(store: FileShortcutStore) { self.store = store }

    var isOpen: Bool { panel != nil }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard panel == nil else { return }
        // Màn hình đang focus = màn hình chứa con trỏ chuột.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let vf = screen.visibleFrame
        let origin = CGPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)

        let p = FilesPopupPanel(contentRect: CGRect(origin: origin, size: size))
        p.onCancel = { [weak self] in self?.close() }
        let root = FilesPopupView(store: store)
        p.contentView = NSHostingView(rootView: root)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            p.animator().alphaValue = 1
        }
        panel = p

        // Bấm ra ngoài popup → đóng.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) { self.close() }
        }
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

/// Bọc FilesPanel (luôn ở dạng mở rộng) trong nền đen bo góc + nút đóng.
private struct FilesPopupView: View {
    @ObservedObject var store: FileShortcutStore
    @State private var selCount = 0

    var body: some View {
        FilesPanel(store: store,
                   expanded: .constant(true),
                   pinned: .constant(true),
                   selCount: $selCount)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 34, y: 18)
            .padding(10)   // chừa chỗ cho shadow không bị cắt
    }
}

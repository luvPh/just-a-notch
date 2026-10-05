import AppKit
import SwiftUI

/// Ghim ảnh nổi trên mọi cửa sổ: kéo để di chuyển, cuộn để phóng to/thu nhỏ,
/// hover hiện ✕ / sao chép / độ mờ, Esc hoặc nhấp đúp để đóng.
@MainActor
enum PinWindow {
    private static var open: [PinPanel] = []

    static func open(_ shot: Shot) {
        let screen = ScreenshotController.screenUnderMouse
        var size = shot.pointSize
        let maxW = screen.visibleFrame.width * 0.6, maxH = screen.visibleFrame.height * 0.6
        let k = min(1, maxW / size.width, maxH / size.height)
        size = CGSize(width: size.width * k, height: size.height * k)
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        let p = PinPanel(shot: shot, frame: CGRect(origin: origin, size: size))
        p.onClose = { [weak p] in
            guard let p else { return }
            p.orderOut(nil)
            open.removeAll { $0 === p }
        }
        open.append(p)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class PinPanel: NSPanel {
    var onClose: (() -> Void)?
    private let aspect: CGFloat

    init(shot: Shot, frame: CGRect) {
        aspect = frame.width / max(1, frame.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = frame.size
        contentView = NSHostingView(rootView: PinView(shot: shot, close: { [weak self] in self?.onClose?() }))
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    /// Cuộn → phóng to/thu nhỏ quanh tâm, giữ tỉ lệ ảnh.
    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
        let f = frame
        let w = min(4000, max(80, f.width * (1 + dy * 0.01)))
        let h = w / aspect
        setFrame(CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: true)
    }
}

private struct PinView: View {
    let shot: Shot
    let close: () -> Void
    @State private var hover = false
    @State private var opacity: Double = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: shot.nsImage).resizable().interpolation(.high)
                .opacity(opacity)
            if hover {
                HStack(spacing: 6) {
                    btn("xmark", "Đóng (Esc)", close)
                    btn("doc.on.doc", "Sao chép") { ScreenshotController.shared.copy(shot) }
                    btn(opacity < 1 ? "circle.fill" : "circle.lefthalf.filled", "Độ mờ") {
                        opacity = opacity < 1 ? 1 : 0.5
                    }
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(hover ? 0.5 : 0.15), lineWidth: 1))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture(count: 2, perform: close)
    }

    private func btn(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(0.65)))
        }
        .buttonStyle(.plain).help(help)
    }
}

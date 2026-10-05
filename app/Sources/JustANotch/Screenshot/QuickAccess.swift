import AppKit
import SwiftUI

/// Thumbnail nổi ở góc dưới-trái sau khi chụp (như "Quick Access Overlay" của CleanShot):
/// hover → Sao chép / Lưu ở giữa, ✕ / ✎ chú thích / 📌 ghim ở các góc; kéo thẻ thả
/// thẳng vào app khác. Tự ẩn sau 10s nếu không hover. Xếp chồng tối đa 4 ảnh.
@MainActor
final class QuickAccess: ObservableObject {
    static let shared = QuickAccess()

    @Published private(set) var shots: [Shot] = []
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var timers: [UUID: DispatchWorkItem] = [:]
    var hovering: Set<UUID> = []

    static let cardSize = CGSize(width: 224, height: 140)
    private let gap: CGFloat = 10, margin: CGFloat = 20

    func show(_ shot: Shot, on screen: NSScreen) {
        self.screen = screen
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            shots.append(shot)
            if shots.count > 4 { shots.removeFirst() }
        }
        ensurePanel()
        layout()
        schedule(shot.id)
    }

    func dismiss(_ id: UUID) {
        timers[id]?.cancel(); timers[id] = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { shots.removeAll { $0.id == id } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if self.shots.isEmpty { self.panel?.orderOut(nil) } else { self.layout() }
        }
    }

    func setHover(_ id: UUID, _ on: Bool) {
        if on { hovering.insert(id); timers[id]?.cancel() } else { hovering.remove(id); schedule(id) }
    }

    private func schedule(_ id: UUID) {
        timers[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering.contains(id) else { return }
            self.dismiss(id)
        }
        timers[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: w)
    }

    private func ensurePanel() {
        guard panel == nil else { panel?.orderFrontRegardless(); return }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: QuickAccessStack(model: self))
        panel = p
        p.orderFrontRegardless()
    }

    /// Panel ôm vừa chồng thẻ, neo góc dưới-trái màn hình vừa chụp.
    private func layout() {
        guard let panel, let screen else { return }
        let n = CGFloat(max(1, shots.count))
        let w = Self.cardSize.width + 2 * margin
        let h = n * Self.cardSize.height + (n - 1) * gap + 2 * margin
        let vf = screen.visibleFrame
        panel.setFrame(CGRect(x: vf.minX, y: vf.minY, width: w, height: h), display: true)
    }
}

private struct QuickAccessStack: View {
    @ObservedObject var model: QuickAccess

    var body: some View {
        VStack(spacing: 10) {
            ForEach(model.shots) { shot in
                ShotCard(shot: shot, model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .bottomLeading)),
                        removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct ShotCard: View {
    let shot: Shot
    @ObservedObject var model: QuickAccess
    @State private var hover = false
    @State private var flash: String?

    private let size = QuickAccess.cardSize
    private let ctrl = ScreenshotController.shared

    var body: some View {
        ZStack {
            // Nền tối + ảnh vừa khung (không cắt).
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.1))
            Image(nsImage: shot.nsImage).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .padding(6)
            if shot.video != nil {
                // Nhãn video: ▶ 0:12 ở góc dưới-trái.
                Label(Self.clock(shot.duration), systemImage: "play.fill")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if hover {
                Color.black.opacity(0.45)
                VStack(spacing: 7) {
                    pill("Sao chép") { ctrl.copy(shot); done("Đã chép") }
                    pill("Lưu") {
                        if let url = ctrl.save(shot) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        done("Đã lưu")
                    }
                }
                corner("xmark", "Đóng", .topLeading) { model.dismiss(shot.id) }
                if let v = shot.video {
                    corner("play.rectangle.fill", "Mở video", .topTrailing) {
                        NSWorkspace.shared.open(v)
                        model.dismiss(shot.id)
                    }
                } else {
                    corner("pencil.tip", "Chú thích", .topTrailing) {
                        AnnotateWindow.open(shot)
                        model.dismiss(shot.id)
                    }
                    corner("pin.fill", "Ghim lên màn hình", .bottomTrailing) {
                        PinWindow.open(shot)
                        model.dismiss(shot.id)
                    }
                }
            }

            if let flash {
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hover = h }
            model.setHover(shot.id, h)
        }
        // Kéo thẻ → thả file PNG vào app khác.
        .onDrag { NSItemProvider(contentsOf: shot.tempURL) ?? NSItemProvider() }
    }

    static func clock(_ t: Double) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func done(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { model.dismiss(shot.id) }
    }

    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 92, height: 28)
                .background(Capsule().fill(.white.opacity(0.95)))
        }
        .buttonStyle(.plain)
    }

    private func corner(_ symbol: String, _ help: String, _ align: Alignment, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(0.6)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
    }
}

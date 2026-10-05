import AppKit
import SwiftUI

/// Lớp chọn vùng chụp: mỗi màn hình một panel phủ kín, hiển thị ẢNH ĐÓNG BĂNG của
/// màn hình đó (chụp trước khi overlay hiện) → chọn vùng chính xác như CleanShot.
///
/// - Kéo: chọn vùng (có kích thước pixel + kính lúp).
/// - Bấm (không kéo): chụp cửa sổ dưới con trỏ; không có cửa sổ → cả màn hình.
/// - Space: bật/tắt chế độ cửa sổ (tô sáng cửa sổ dưới con trỏ).
/// - Enter: cả màn hình · Esc: huỷ.
@MainActor
final class SelectionSession {
    enum Pick {
        case area(CGRect)                       // toạ độ cục bộ màn hình (pt, gốc trên-trái)
        case window(CGWindowID, CGRect)         // id + khung cục bộ
        case full
    }

    struct Frozen { let screen: NSScreen; let image: CGImage }

    private var panels: [ShotOverlayPanel] = []
    private let model = SelectionModel()
    private var done: ((Frozen, Pick)?) -> Void
    private var finished = false

    init(frozen: [Frozen], windowMode: Bool, verb: String = "chụp", done: @escaping ((Frozen, Pick)?) -> Void) {
        self.done = done
        model.windowMode = windowMode
        let windows = ScreenGrabber.onScreenWindows()
        for f in frozen {
            let q = ScreenGrabber.quartzFrame(of: f.screen)
            // Khung cửa sổ đổi sang toạ độ cục bộ màn hình này (gốc trên-trái).
            let local = windows.compactMap { w -> SelectionView.Win? in
                let r = w.frame.intersection(q)
                guard !r.isNull, r.width > 20, r.height > 20 else { return nil }
                return .init(id: w.id, rect: w.frame.offsetBy(dx: -q.minX, dy: -q.minY))
            }
            let panel = ShotOverlayPanel(screen: f.screen)
            let view = SelectionView(
                image: f.image, size: f.screen.frame.size, windows: local, model: model, verb: verb,
                finish: { [weak self] pick in self?.finish(f, pick) })
            panel.contentView = CrosshairHostingView(rootView: view)
            panel.onKey = { [weak self] e in self?.key(e, frozen: f) ?? false }
            panels.append(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        for p in panels { p.orderFrontRegardless() }
        // Panel dưới con trỏ nhận bàn phím.
        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKey()
    }

    private func key(_ e: NSEvent, frozen: Frozen) -> Bool {
        switch e.keyCode {
        case 53: finish(nil, nil); return true                            // Esc
        case 49: model.windowMode.toggle(); return true                   // Space
        case 36, 76: finish(frozen, .full); return true                   // Enter
        default: return false
        }
    }

    private func finish(_ f: Frozen?, _ pick: Pick?) {
        guard !finished else { return }
        finished = true
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        if let f, let pick { done((f, pick)) } else { done(nil) }
    }
}

/// Trạng thái dùng chung giữa các màn hình.
@MainActor
final class SelectionModel: ObservableObject {
    @Published var windowMode = false
}

final class ShotOverlayPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

/// Con trỏ chữ thập trên toàn overlay.
final class CrosshairHostingView<V: View>: NSHostingView<V> {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SelectionView: View {
    struct Win { let id: CGWindowID; let rect: CGRect }

    let image: CGImage
    let size: CGSize
    let windows: [Win]
    @ObservedObject var model: SelectionModel
    var verb: String = "chụp"
    let finish: (SelectionSession.Pick) -> Void

    @State private var hover: CGPoint?
    @State private var start: CGPoint?
    @State private var current: CGPoint?
    /// Chỉ dùng cho snapshot test: dựng sẵn trạng thái đang kéo.
    var debugDrag: (CGPoint, CGPoint)? = nil

    private var pxScale: CGFloat { CGFloat(image.width) / max(1, size.width) }

    private var dragRect: CGRect? {
        guard let s = start, let c = current, abs(c.x - s.x) > 2 || abs(c.y - s.y) > 2 else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    private func window(at p: CGPoint) -> Win? { windows.first { $0.rect.contains(p) } }

    /// Vùng sáng: đang kéo → vùng kéo; chế độ cửa sổ → cửa sổ dưới con trỏ.
    private var hole: CGRect? {
        if let r = dragRect { return r }
        if model.windowMode, let p = hover, let w = window(at: p) { return w.rect }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: pxScale).resizable().frame(width: size.width, height: size.height)

            // Phủ tối, khoét lỗ ở vùng chọn.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                if let h = hole { p.addRect(h) }
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
            .animation(.easeOut(duration: 0.12), value: hole)

            if let h = hole {
                Rectangle()
                    .fill(model.windowMode && dragRect == nil ? Color.accentColor.opacity(0.12) : .clear)
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.95), lineWidth: 1))
                    .frame(width: h.width, height: h.height)
                    .offset(x: h.minX, y: h.minY)
                    .allowsHitTesting(false)
                sizeBadge(h)
            }

            if dragRect == nil, !model.windowMode, let p = hover { crosshair(p) }
            hint
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onAppear { if let d = debugDrag { start = d.0; current = d.1; hover = d.1 } }
        .onContinuousHover { phase in
            if case let .active(p) = phase { hover = p } else { hover = nil }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if start == nil { start = v.startLocation }
                    current = v.location
                    hover = v.location
                }
                .onEnded { v in
                    defer { start = nil; current = nil }
                    if let r = dragRect, r.width >= 4, r.height >= 4 {
                        finish(.area(r.integral))
                    } else if let w = window(at: v.location) {
                        finish(.window(w.id, w.rect))
                    } else {
                        finish(.full)
                    }
                }
        )
    }

    // MARK: Thành phần

    private func sizeBadge(_ r: CGRect) -> some View {
        let text = "\(Int((r.width * pxScale).rounded())) × \(Int((r.height * pxScale).rounded()))"
        let below = r.maxY + 30 < size.height
        return Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(.black.opacity(0.75)))
            .fixedSize()
            .offset(x: max(4, min(r.minX, size.width - 110)), y: below ? r.maxY + 6 : max(4, r.minY - 28))
            .allowsHitTesting(false)
    }

    private func crosshair(_ p: CGPoint) -> some View {
        Path { path in
            path.move(to: CGPoint(x: p.x, y: 0)); path.addLine(to: CGPoint(x: p.x, y: size.height))
            path.move(to: CGPoint(x: 0, y: p.y)); path.addLine(to: CGPoint(x: size.width, y: p.y))
        }
        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    /// Kính lúp: cắt 15×15pt quanh con trỏ từ ảnh đóng băng, phóng 8 lần, lưới pixel giữa.
    private func loupe(_ p: CGPoint) -> some View {
        let d: CGFloat = 120, span: CGFloat = 15
        let src = CGRect(x: (p.x - span / 2) * pxScale, y: (p.y - span / 2) * pxScale,
                         width: span * pxScale, height: span * pxScale).integral
        let crop = image.cropping(to: src)
        // Đặt dưới-phải con trỏ, lật khi sát mép.
        var x = p.x + 22, y = p.y + 22
        if x + d > size.width { x = p.x - 22 - d }
        if y + d + 22 > size.height { y = p.y - 22 - d - 22 }
        return VStack(spacing: 4) {
            ZStack {
                Color.black
                if let crop { Image(decorative: crop, scale: 1).interpolation(.none).resizable() }
                // ô pixel trung tâm
                Rectangle().strokeBorder(.white, lineWidth: 1).frame(width: d / span, height: d / span)
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            Text("\(Int(p.x * pxScale)), \(Int(p.y * pxScale))")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(.black.opacity(0.75)))
        }
        .offset(x: x, y: y)
        .allowsHitTesting(false)
    }

    private var hint: some View {
        HStack(spacing: 14) {
            key("Kéo", "\(verb) vùng")
            key("Bấm", "\(verb) cửa sổ")
            key("Space", model.windowMode ? "chế độ vùng" : "chế độ cửa sổ")
            key("↩", "\(verb) cả màn hình")
            key("Esc", "huỷ")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).frame(height: 30)
        .background(Capsule().fill(.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .frame(width: size.width, height: size.height - 28, alignment: .bottom)
        .allowsHitTesting(false)
        .opacity(dragRect == nil ? 1 : 0)
    }

    private func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(k).font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 5).frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.18)))
            Text(label).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
    }
}

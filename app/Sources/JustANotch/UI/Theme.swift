import SwiftUI

// MARK: - Màu động theo giao diện

extension Color {
    /// "Mực" của notch: trắng trên nền tối, gần-đen trên kính sáng. Tự đổi theo
    /// `colorScheme` của vùng giao diện (notch thu gọn luôn tối, mở rộng theo cài đặt).
    /// Dùng `.ink.opacity(x)` thay cho `.ink.opacity(x)` ở mọi chỗ vẽ trong notch.
    static let ink = Color(nsColor: NSColor(name: "notch.ink") { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white : NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
    })
    /// Ngược với ink — chữ trên nền ink đặc (chip đang bật, nút tab đang chọn…).
    static let inkInverse = Color(nsColor: NSColor(name: "notch.inkInverse") { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .black : .white
    })
}

extension ShapeStyle where Self == Color {
    static var ink: Color { .ink }
    static var inkInverse: Color { .inkInverse }
}

/// Design tokens dùng chung cho mọi tab trong notch.
enum NotchTheme {
    /// Màu chủ đạo — đỏ cam của Lịch.
    static let accent = Color(red: 0.96, green: 0.36, blue: 0.33)
    /// Nền ô/thẻ trên nền đen của notch.
    static let card = Color.ink.opacity(0.08)
    static let cardHover = Color.ink.opacity(0.13)
    static let cardRadius: CGFloat = 12
    static let secondaryText = Color.ink.opacity(0.55)
    /// Tiêu đề hàng công cụ đầu mỗi tab (Tháng 10, Hôm nay…).
    static let toolbarTitle = Font.system(size: 13, weight: .semibold)
}

/// Chip dạng viên thuốc: bật = trắng chữ đen, tắt = ô xám mờ.
struct NotchChip: View {
    let title: String
    var symbol: String? = nil
    var badge: String? = nil
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
                Text(title).font(.system(size: 10.5, weight: .semibold))
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(on ? Color.inkInverse.opacity(0.45) : .ink.opacity(0.4))
                }
            }
            .foregroundStyle(on ? Color.inkInverse : .ink.opacity(0.85))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(on ? Color.ink : NotchTheme.card))
        }
        .buttonStyle(.plain)
    }
}

/// Nút icon tròn nhỏ, cùng cỡ trên mọi tab.
struct NotchIconButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? Color.inkInverse : .ink.opacity(hover ? 0.95 : 0.65))
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? Color.ink : (hover ? NotchTheme.cardHover : NotchTheme.card)))
        }
        .buttonStyle(.plain).help(help)
        .onHover { hover = $0 }
    }
}

/// Trạng thái trống: icon trong vòng tròn + 1 dòng tiêu đề + gợi ý nhỏ.
struct NotchEmptyState: View {
    let symbol: String
    let title: String
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NotchTheme.accent.opacity(0.15)))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.ink.opacity(0.85))
            if let hint {
                Text(hint).font(.system(size: 10.5)).foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Mờ dần ở hai mép (ngang hoặc dọc) thay vì cắt cụt — dùng cho ScrollView.
    func edgeFade(_ axis: Axis = .horizontal, _ length: CGFloat = 18, leading: Bool = true) -> some View {
        mask {
            GeometryReader { g in
                let total = axis == .horizontal ? g.size.width : g.size.height
                let f = min(0.45, length / max(total, 1))
                LinearGradient(stops: [.init(color: leading ? .clear : .black, location: 0),
                                       .init(color: .black, location: f),
                                       .init(color: .black, location: 1 - f),
                                       .init(color: .clear, location: 1)],
                               startPoint: axis == .horizontal ? .leading : .top,
                               endPoint: axis == .horizontal ? .trailing : .bottom)
            }
        }
    }

    /// Bề mặt "liquid glass" trên nền đen của notch: nền trong mờ có gradient,
    /// viền sáng ở mép trên tan dần xuống dưới, ánh sáng khi hover.
    func notchGlass(cornerRadius r: CGFloat = NotchTheme.cardRadius, hover: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return self
            .background(
                shape.fill(LinearGradient(colors: [.ink.opacity(hover ? 0.16 : 0.11), .ink.opacity(hover ? 0.07 : 0.04)],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.ink.opacity(hover ? 0.42 : 0.24), .ink.opacity(0.04),
                                                           .ink.opacity(hover ? 0.14 : 0.06)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .clipShape(shape)
    }
}

/// Đặt làm background BÊN TRONG nội dung của một ScrollView ngang: cuộn chuột dọc
/// (bánh xe / vuốt dọc) được đổi thành cuộn ngang — không cần giữ Shift.
struct VerticalWheelToHorizontal: NSViewRepresentable {
    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ v: WheelView, context: Context) {}

    final class WheelView: NSView {
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let sv = self.enclosingScrollView, let win = sv.window,
                      win.convertToScreen(sv.convert(sv.bounds, to: nil)).contains(NSEvent.mouseLocation)
                else { return e }
                let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
                guard abs(dy) > abs(dx) else { return e }   // vuốt ngang: để ScrollView tự xử lý
                let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
                let clip = sv.contentView
                let maxX = max(0, (sv.documentView?.frame.width ?? 0) - clip.bounds.width)
                let x = min(maxX, max(0, clip.bounds.origin.x - dy * k))
                clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
                sv.reflectScrolledClipView(clip)
                return nil
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

/// Thẻ kính có trạng thái hover (sáng nền + viền) — dùng cho các hàng bấm được.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 10
    @ViewBuilder let content: Content
    @State private var hover = false

    var body: some View {
        content
            .notchGlass(cornerRadius: cornerRadius, hover: hover)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Thanh trượt kiểu notch (cùng dáng thanh âm lượng nhạc): vạch mảnh, núm trắng
/// phình khi kéo. Thay cho `Slider` hệ thống (xanh dương, lạc tông app).
struct NotchSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEnded: () -> Void = {}
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false

    var body: some View {
        let r: CGFloat = 5
        GeometryReader { g in
            let usable = max(1, g.size.width - 2 * r)
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let cx = r + min(1, max(0, f)) * usable
            let d: CGFloat = dragging ? 10 : 7
            ZStack(alignment: .leading) {
                Capsule().fill(.ink.opacity(0.12)).frame(height: 3)
                Capsule().fill(.ink.opacity(0.75)).frame(width: max(3, cx), height: 3)
                Circle().fill(.ink.opacity(0.9)).frame(width: d, height: d).offset(x: cx - d / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    dragging = true
                    let t = min(1, max(0, Double((v.location.x - r) / usable)))
                    value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                }
                .onEnded { _ in dragging = false; onEnded() })
        }
        .frame(height: 12)
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
    }
}


// MARK: - Nền kính sáng

/// Kính mờ hệ thống làm mờ MÀN HÌNH phía sau cửa sổ (behindWindow). View AppKit
/// không bị SwiftUI `clipShape` cắt, nên tự cắt bằng `maskImage` vẽ từ `shape`.
/// `size` + `shape` được truyền vào ở MỖI khung hình (xem `AnimatedGlass`) để mặt nạ
/// khớp hình notch cả trong lúc hiệu ứng mở/đóng đang chạy.
struct VisualEffectBlur<S: Shape>: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    let shape: S
    let size: CGSize

    final class MaskedView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // chỉ là nền, không nuốt chuột
    }

    func makeNSView(context: Context) -> MaskedView {
        let v = MaskedView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .aqua)
        return v
    }

    func updateNSView(_ v: MaskedView, context: Context) {
        v.material = material
        guard size.width > 0, size.height > 0 else { return }
        let path = shape.path(in: CGRect(origin: .zero, size: size)).cgPath
        v.maskImage = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path); ctx.setFillColor(.black); ctx.fillPath()
            return true
        }
    }
}

/// Kính hệ thống đặt ở TẦNG GỐC (khung cố định phủ cả panel, không bao giờ bị
/// scale/offset/co giãn) — view AppKit không theo được các biến đổi đó của SwiftUI nên
/// trước đây kính lệch khỏi notch khi đang animate. Ở đây chỉ mặt nạ di chuyển: vị trí /
/// cỡ / bán kính bề mặt được nội suy theo từng khung (Animatable) rồi cắt kính đúng chỗ.
struct SurfaceGlass: View, Animatable {
    var width: CGFloat, height: CGFloat
    var offsetX: CGFloat, offsetY: CGFloat
    var scale: CGFloat
    var bottom: CGFloat, inverse: CGFloat, top: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
                                       AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(.init(.init(width, height), .init(offsetX, offsetY)), .init(.init(scale, bottom), .init(inverse, top))) }
        set {
            width = newValue.first.first.first; height = newValue.first.first.second
            offsetX = newValue.first.second.first; offsetY = newValue.first.second.second
            scale = newValue.second.first.first; bottom = newValue.second.first.second
            inverse = newValue.second.second.first; top = newValue.second.second.second
        }
    }

    /// NotchShape đặt vào đúng khung bề mặt trong toạ độ panel.
    private struct Placed: Shape {
        let base: NotchShape
        let rect: CGRect
        func path(in _: CGRect) -> Path {
            base.path(in: CGRect(origin: .zero, size: rect.size)).offsetBy(dx: rect.minX, dy: rect.minY)
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = width * scale, h = height * scale
            // Bề mặt canh giữa panel, neo mép trên (scaleEffect anchor .top) rồi mới offset.
            let rect = CGRect(x: g.size.width / 2 + offsetX - w / 2, y: offsetY, width: w, height: h)
            VisualEffectBlur(material: .popover,
                             shape: Placed(base: NotchShape(bottom: bottom, inverse: inverse, top: top), rect: rect),
                             size: g.size)
        }
        .allowsHitTesting(false)
    }
}

/// Nền "liquid glass" sáng của notch mở rộng / pill. Dạng notch có quầng đen mềm toả
/// từ camera (lõi đen đặc đúng cỡ camera để khớp phần cứng, tan dần ra kính sáng).
struct NotchGlassBackdrop: View {
    let pill: Bool
    /// false = kính thật (.glassEffect) tự lo độ đọc được → không phủ lớp trắng.
    var frosted = true
    let coreWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        // Nền chỉ lấp đầy khung được giao; khói/lõi nằm trong overlay nên KHÔNG BAO GIỜ
        // làm bề mặt notch phình theo (khói rộng hơn notch → trước đây kéo vỡ bố cục).
        // Lớp kính hệ thống thật nằm ở tầng gốc (SurfaceGlass); ở đây chỉ phủ màu + khói.
        Color.clear
            .overlay {
                if frosted {
                    LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .top) { smoke }
            .clipped()
            .allowsHitTesting(false)
    }

    @ViewBuilder private var smoke: some View {
        ZStack(alignment: .top) {
            if !pill {
                // Khói: dải màu elip trên khung chữ nhật (không có mép hình) → tan thật mềm.
                Rectangle()
                    .fill(EllipticalGradient(stops: [
                        .init(color: .black.opacity(0.95), location: 0),
                        .init(color: .black.opacity(0.75), location: 0.25),
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.1).opacity(0.42), location: 0.5),
                        .init(color: Color(red: 0.1, green: 0.1, blue: 0.16).opacity(0.15), location: 0.75),
                        .init(color: .clear, location: 1),
                    ], center: .top, startRadiusFraction: 0, endRadiusFraction: 0.5))   // = 0 đúng ở mép khung
                    .frame(width: coreWidth * 3.2, height: notchHeight * 5)
                    .offset(y: -notchHeight * 0.6)
                    .blur(radius: 10)
                UnevenRoundedRectangle(bottomLeadingRadius: notchHeight * 0.45, bottomTrailingRadius: notchHeight * 0.45)
                    .fill(.black)
                    .frame(width: coreWidth, height: notchHeight)
                    .blur(radius: 3)
            }
        }
        .frame(width: 0, height: 0, alignment: .top)   // không chiếm chỗ; con vẽ tràn ra
    }
}

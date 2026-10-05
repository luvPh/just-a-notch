import SwiftUI

/// Design tokens dùng chung cho mọi tab trong notch.
enum NotchTheme {
    /// Màu chủ đạo — đỏ cam của Lịch.
    static let accent = Color(red: 0.96, green: 0.36, blue: 0.33)
    /// Nền ô/thẻ trên nền đen của notch.
    static let card = Color.white.opacity(0.08)
    static let cardHover = Color.white.opacity(0.13)
    static let cardRadius: CGFloat = 12
    static let secondaryText = Color.white.opacity(0.55)
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
                        .foregroundStyle(on ? .black.opacity(0.45) : .white.opacity(0.4))
                }
            }
            .foregroundStyle(on ? .black : .white.opacity(0.85))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(on ? Color.white : NotchTheme.card))
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
                .foregroundStyle(active ? .black : .white.opacity(hover ? 0.95 : 0.65))
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? Color.white : (hover ? NotchTheme.cardHover : NotchTheme.card)))
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
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
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
                shape.fill(LinearGradient(colors: [.white.opacity(hover ? 0.16 : 0.11), .white.opacity(hover ? 0.07 : 0.04)],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(hover ? 0.42 : 0.24), .white.opacity(0.04),
                                                           .white.opacity(hover ? 0.14 : 0.06)],
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

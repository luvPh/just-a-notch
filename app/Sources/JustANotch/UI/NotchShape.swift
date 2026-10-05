import SwiftUI

/// Physical-notch shape: flat top edge, concave (inverse) top corners that melt
/// into the bezel, rounded bottom corners. Grows downward from the notch.
struct NotchShape: Shape {
    var bottom: CGFloat
    var inverse: CGFloat
    /// Bo lồi ở hai góc trên (chế độ pill, màn hình không có notch). 0 = phẳng.
    var top: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(bottom, inverse), top) }
        set { bottom = newValue.first.first; inverse = newValue.first.second; top = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        if top > 0.5 {
            // Pill: hình chữ nhật bo đều, góc dưới theo `bottom`, góc trên theo `top`.
            let half = min(rect.width, rect.height) / 2
            let t = min(top, half), b = min(bottom, half)
            return UnevenRoundedRectangle(topLeadingRadius: t, bottomLeadingRadius: b,
                                          bottomTrailingRadius: b, topTrailingRadius: t,
                                          style: .continuous).path(in: rect)
        }
        let ir = max(0, min(inverse, rect.width / 2 - 1))
        let br = max(0, min(bottom, rect.height - ir - 1, rect.width / 2 - ir - 1))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if ir > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.maxX - ir, y: rect.minY + ir),
                           control: CGPoint(x: rect.maxX - ir, y: rect.minY))
        }
        // Góc dưới "continuous" (squircle) như Apple: đường cong bắt đầu sớm hơn
        // bán kính (×1.28) và kéo tiếp tuyến dài → không còn điểm gãy độ cong.
        let k: CGFloat = 1.28
        let bs = min(br * k, (rect.width / 2 - ir), rect.height - ir)
        let rx = rect.maxX - ir, lx = rect.minX + ir, by = rect.maxY
        p.addLine(to: CGPoint(x: rx, y: by - bs))
        p.addCurve(to: CGPoint(x: rx - bs, y: by),
                   control1: CGPoint(x: rx, y: by - bs * 0.36),
                   control2: CGPoint(x: rx - bs * 0.36, y: by))
        p.addLine(to: CGPoint(x: lx + bs, y: by))
        p.addCurve(to: CGPoint(x: lx, y: by - bs),
                   control1: CGPoint(x: lx + bs * 0.36, y: by),
                   control2: CGPoint(x: lx, y: by - bs * 0.36))
        p.addLine(to: CGPoint(x: rect.minX + ir, y: rect.minY + ir))
        if ir > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                           control: CGPoint(x: rect.minX + ir, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

/// Alcove-style soft transition: content blurs + fades as it enters/leaves.
private struct BlurOpacity: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}
extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurOpacity(radius: 7, opacity: 0), identity: BlurOpacity(radius: 0, opacity: 1))
    }
}

/// Album artwork with a gradient fallback.
struct Artwork: View {
    let data: Data?
    var corner: CGFloat = 6
    var body: some View {
        if let data, let img = NSImage(data: data) {
            // Ảnh nằm trong overlay của khung → lấp đầy rồi CẮT đúng theo khung
            // (ảnh 16:9 như thumbnail YouTube không tràn ra hai bên).
            Color.clear
                .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 0.98),
                                              Color(red: 0.78, green: 0.42, blue: 0.92)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
        }
    }
}

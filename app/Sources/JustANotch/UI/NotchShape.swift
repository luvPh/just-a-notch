import SwiftUI

/// Physical-notch shape: flat top edge, concave (inverse) top corners that melt
/// into the bezel, rounded bottom corners. Grows downward from the notch.
struct NotchShape: Shape {
    var bottom: CGFloat
    var inverse: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottom, inverse) }
        set { bottom = newValue.first; inverse = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let ir = max(0, min(inverse, rect.width / 2 - 1))
        let br = max(0, min(bottom, rect.height - ir - 1, rect.width / 2 - ir - 1))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if ir > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.maxX - ir, y: rect.minY + ir),
                           control: CGPoint(x: rect.maxX - ir, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX - ir, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ir - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + ir + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ir, y: rect.maxY - br),
                       control: CGPoint(x: rect.minX + ir, y: rect.maxY))
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
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
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

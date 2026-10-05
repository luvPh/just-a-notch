import SwiftUI

// MARK: - Codex: terminal pixel >_

/// Cửa sổ terminal pixel (dữ liệu sinh bởi `app/scripts/gen_sprites.py` → `SpriteData.swift`).
enum CodexTerm {
    enum Mode { case work, alert, happy }

    static func timeline(_ m: Mode) -> [[String]] {
        switch m {
        case .work:  return work.map { workFrames[$0] }
        case .alert: return alert.map { alertFrames[$0] }
        case .happy: return happy.map { happyFrames[$0] }
        }
    }
}

struct CodexTermSprite: View {
    let mode: CodexTerm.Mode
    var pixel: CGFloat = 1
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        let frames = CodexTerm.timeline(mode)
        Group {
            if reduceMotion {
                PixelCanvas(frame: frames[frames.count - 1], pixel: pixel, palette: CodexTerm.palette)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / CodexTerm.fps)) { ctx in
                    let i = Int(ctx.date.timeIntervalSince(start) * CodexTerm.fps)
                    PixelCanvas(frame: frames[i % frames.count], pixel: pixel, palette: CodexTerm.palette)
                }
            }
        }
        .frame(width: CGFloat(CodexTerm.width) * pixel, height: CGFloat(CodexTerm.height) * pixel)
    }
}

// MARK: - Codex: logo OpenAI biến hình

/// 6 mắt xích bo tròn (viền) xếp đều 60°. Mỗi hình = (bán kính đặt mắt xích `r`, độ xoắn
/// so với tiếp tuyến `twist`°, dài `l`, rộng `w`) — nút thắt ≈ logo OpenAI, vòng lục
/// giác, bông hoa. Khung chuyển là nội suy các số này (không chồng mờ).
struct KnotShape {
    var r: Double, twist: Double, l: Double, w: Double

    static let knot   = KnotShape(r: 0.34, twist: 32, l: 0.92, w: 0.34)
    static let hexRing = KnotShape(r: 0.62, twist: 0, l: 0.72, w: 0.22)
    static let flower = KnotShape(r: 0.46, twist: 90, l: 0.8, w: 0.3)

    static func lerp(_ a: KnotShape, _ b: KnotShape, _ f: Double) -> KnotShape {
        KnotShape(r: a.r + (b.r - a.r) * f, twist: a.twist + (b.twist - a.twist) * f,
                  l: a.l + (b.l - a.l) * f, w: a.w + (b.w - a.w) * f)
    }
}

struct OpenAIKnot: View {
    var size: CGFloat
    var color: Color = Color(red: 0.93, green: 0.95, blue: 0.97)
    let reduceMotion: Bool
    @State private var start = Date()

    static let keyframes: [KnotShape] = [.knot, .hexRing, .knot, .flower]
    static let fps = 8.0
    static let framesPerMorph = 6
    static var loopDuration: TimeInterval { Double(keyframes.count * framesPerMorph) / fps }

    static func pose(at t: TimeInterval) -> (shape: KnotShape, angle: Double) {
        let n = Int(t * fps)
        let seg = (n / framesPerMorph) % keyframes.count
        let f = Double(n % framesPerMorph) / Double(framesPerMorph)
        let e = f * f * (3 - 2 * f)
        return (KnotShape.lerp(keyframes[seg], keyframes[(seg + 1) % keyframes.count], e), Double(n) * 2.5)
    }

    var body: some View {
        Group {
            if reduceMotion {
                OpenAIKnotCanvas(shape: .knot, angle: 0, size: size, color: color)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / Self.fps)) { ctx in
                    let p = Self.pose(at: ctx.date.timeIntervalSince(start))
                    OpenAIKnotCanvas(shape: p.shape, angle: p.angle, size: size, color: color)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct OpenAIKnotCanvas: View {
    let shape: KnotShape
    let angle: Double
    let size: CGFloat
    var color: Color = Color(red: 0.93, green: 0.95, blue: 0.97)

    var body: some View {
        Canvas { ctx, sz in
            let R = min(sz.width, sz.height) / 2 * 0.86
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let len = shape.l * R, wid = shape.w * R
            var path = Path()
            for k in 0..<6 {
                let a = (Double(k) * 60 + angle) * .pi / 180
                let link = Path(roundedRect: CGRect(x: -len / 2, y: -wid / 2, width: len, height: wid),
                                cornerRadius: wid / 2)
                // Đặt mắt xích ở bán kính r, hướng theo tiếp tuyến rồi xoắn thêm `twist`.
                let t = CGAffineTransform(rotationAngle: shape.twist * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: 0, y: -shape.r * R))
                    .concatenating(CGAffineTransform(rotationAngle: a))
                    .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
                path.addPath(link, transform: t)
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, R * 0.11), lineJoin: .round))
        }
        .shadow(color: color.opacity(0.35), radius: size * 0.12)
        .frame(width: size, height: size)
    }
}

// Vẽ icon app "Just a Notch" bằng CoreGraphics (không cần Xcode/ImageMagick).
//   swift scripts/make_icon.swift <variant> <out.png>
// variant: aurora | graphite | kitty
// build_app.sh dùng output 1024px → iconset → AppIcon.icns.
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, a,
    ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: cs,
               colors: stops.map { rgb($0.0, $0.1) } as CFArray,
               locations: stops.map { $0.2 })!
}

/// Squircle kiểu Big Sur (siêu ellipse n≈5) trong lưới 824/1024 của Apple.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// Tai thỏ treo từ mép trên: vai lõm (shoulder) + 2 góc đáy bo tròn.
func notch(cx: CGFloat, top: CGFloat, width w: CGFloat, depth d: CGFloat,
           radius r: CGFloat, shoulder s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let l = cx - w / 2, rt = cx + w / 2, bottom = top + d
    p.move(to: CGPoint(x: l - s, y: top - 40))
    p.addLine(to: CGPoint(x: l - s, y: top))
    p.addArc(tangent1End: CGPoint(x: l, y: top), tangent2End: CGPoint(x: l, y: top + s), radius: s)
    p.addArc(tangent1End: CGPoint(x: l, y: bottom), tangent2End: CGPoint(x: cx, y: bottom), radius: r)
    p.addArc(tangent1End: CGPoint(x: rt, y: bottom), tangent2End: CGPoint(x: rt, y: top), radius: r)
    p.addArc(tangent1End: CGPoint(x: rt, y: top), tangent2End: CGPoint(x: rt + s, y: top), radius: s)
    p.addLine(to: CGPoint(x: rt + s, y: top - 40))
    p.closeSubpath()
    return p
}

func radial(_ ctx: CGContext, _ c: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ a: CGFloat) {
    ctx.drawRadialGradient(gradient([(hex, a, 0), (hex, 0, 1)]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Sóng nhạc: các thanh bo tròn, gradient dọc.
func waveform(_ ctx: CGContext, centerX: CGFloat, centerY: CGFloat, heights: [CGFloat],
              barWidth: CGFloat, gap: CGFloat, colors: CGGradient) {
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = centerX - total / 2
    let bars = CGMutablePath()
    for h in heights {
        bars.addPath(roundedRect(CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h), barWidth / 2))
        x += barWidth + gap
    }
    let maxH = heights.max() ?? 0
    fillGradient(ctx, bars, colors, from: CGPoint(x: 0, y: centerY - maxH / 2),
                 to: CGPoint(x: 0, y: centerY + maxH / 2))
}

func render(_ variant: String) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Toạ độ gốc trên-trái cho dễ nghĩ.
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    let cx = body.midX

    // Bóng đổ dưới thân icon (offset tính theo base space, y hướng lên).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState(); ctx.addPath(shape); ctx.clip()

    switch variant {
    case "graphite":
        ctx.drawLinearGradient(gradient([(0xF7F8FA, 1, 0), (0xDADDE3, 1, 0.55), (0xB9BDC6, 1, 1)]),
                               start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        radial(ctx, CGPoint(x: cx, y: body.minY + 170), 420, 0xFFFFFF, 0.7)
    case "kitty":
        ctx.drawLinearGradient(gradient([(0xFFC3A0, 1, 0), (0xFF7EB0, 1, 0.55), (0xA77BFF, 1, 1)]),
                               start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
        radial(ctx, CGPoint(x: body.minX + 160, y: body.maxY - 120), 420, 0xFFE9A8, 0.55)
    default: // aurora
        ctx.drawLinearGradient(gradient([(0x0B0A1F, 1, 0), (0x1E1650, 1, 0.45), (0x4A2383, 1, 1)]),
                               start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        radial(ctx, CGPoint(x: cx + 120, y: body.maxY + 60), 560, 0xFF7A4D, 0.75)
        radial(ctx, CGPoint(x: body.minX + 40, y: body.maxY - 160), 460, 0x3D7BFF, 0.45)
        radial(ctx, CGPoint(x: cx, y: body.minY + 300), 360, 0x6C5CFF, 0.35)
    }

    // Tai thỏ.
    let top = body.minY
    let (w, d, r): (CGFloat, CGFloat, CGFloat) = variant == "graphite" ? (340, 160, 64) : (440, 232, 92)
    let notchPath = notch(cx: cx, top: top, width: w, depth: d, radius: r, shoulder: variant == "graphite" ? 40 : 48)

    // Quầng sáng nhẹ dưới tai thỏ (như live activity đang chạy).
    if variant != "graphite" {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60,
                      color: variant == "kitty" ? rgb(0x9C2F6A, 0.30) : rgb(0x5AF2C4, 0.28))
        ctx.addPath(notchPath); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
        ctx.restoreGState()
    } else {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: rgb(0x000000, 0.25))
        ctx.addPath(notchPath); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(notchPath); ctx.setFillColor(rgb(0x050507)); ctx.fillPath()

    let midY = top + d * 0.56
    switch variant {
    case "graphite":
        // Cụm camera: vòng lens + đèn xanh.
        ctx.setFillColor(rgb(0x1A1D2B)); ctx.fillEllipse(in: CGRect(x: cx - 30, y: midY - 30, width: 60, height: 60))
        ctx.setFillColor(rgb(0x2D3F7A)); ctx.fillEllipse(in: CGRect(x: cx - 16, y: midY - 16, width: 32, height: 32))
        ctx.setFillColor(rgb(0x8FB0FF, 0.8)); ctx.fillEllipse(in: CGRect(x: cx - 9, y: midY - 11, width: 9, height: 9))
        ctx.setFillColor(rgb(0x34E27A)); ctx.fillEllipse(in: CGRect(x: cx + 52, y: midY - 9, width: 18, height: 18))
    case "kitty":
        // Mặt mèo ":3" — hai mắt + miệng ω + má hồng.
        let eyeW: CGFloat = 36, eyeH: CGFloat = 58, eyeDX: CGFloat = 112, eyeY = midY - 34
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.addPath(roundedRect(CGRect(x: cx - eyeDX - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH), eyeW / 2))
        ctx.addPath(roundedRect(CGRect(x: cx + eyeDX - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH), eyeW / 2))
        ctx.fillPath()
        let mouth = CGMutablePath(), mr: CGFloat = 26, my = midY + 36
        mouth.addArc(center: CGPoint(x: cx - mr, y: my), radius: mr, startAngle: 0, endAngle: .pi, clockwise: false)
        mouth.move(to: CGPoint(x: cx + 2 * mr, y: my))
        mouth.addArc(center: CGPoint(x: cx + mr, y: my), radius: mr, startAngle: 0, endAngle: .pi, clockwise: false)
        ctx.addPath(mouth); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(15); ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.setFillColor(rgb(0xFF8DB8, 0.9))
        ctx.fillEllipse(in: CGRect(x: cx - eyeDX - 62, y: midY + 18, width: 64, height: 36))
        ctx.fillEllipse(in: CGRect(x: cx + eyeDX - 2, y: midY + 18, width: 64, height: 36))
    default:
        // Now-playing: ảnh bìa + sóng nhạc.
        let art = CGRect(x: cx - w / 2 + 50, y: midY - 54, width: 108, height: 108)
        fillGradient(ctx, roundedRect(art, 28), gradient([(0xFFB35C, 1, 0), (0xFF4F8B, 1, 0.55), (0x8B5CFF, 1, 1)]),
                     from: CGPoint(x: art.minX, y: art.minY), to: CGPoint(x: art.maxX, y: art.maxY))
        ctx.setFillColor(rgb(0xFFFFFF, 0.92))
        ctx.fillEllipse(in: CGRect(x: art.midX - 22, y: art.midY - 22, width: 44, height: 44))
        ctx.setFillColor(rgb(0xFF4F8B)); ctx.fillEllipse(in: CGRect(x: art.midX - 8, y: art.midY - 8, width: 16, height: 16))
        waveform(ctx, centerX: cx + 76, centerY: midY, heights: [48, 104, 74, 124, 62],
                 barWidth: 22, gap: 16, colors: gradient([(0x7CF7D4, 1, 0), (0x4FB8FF, 1, 1)]))
    }

    ctx.restoreGState()

    // Viền sáng mảnh bên trong thân icon cho cảm giác kính.
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, variant == "graphite" ? 0.6 : 0.14)); ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make_icon.swift <aurora|graphite|kitty> <out.png>"); exit(1) }
let rep = NSBitmapImageRep(cgImage: render(args[1]))
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")

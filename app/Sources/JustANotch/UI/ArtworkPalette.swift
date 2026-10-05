import SwiftUI
import AppKit

/// Hai màu chủ đạo của ảnh bìa (nửa trên / nửa dưới), tăng độ bão hoà nhẹ —
/// dùng cho nền "ambient" của tab Đang phát và màu sóng nhạc.
enum ArtworkPalette {
    struct Tint: Equatable { var primary: Color; var secondary: Color }

    @MainActor private static var cache: [Int: Tint] = [:]

    @MainActor static func tint(for data: Data?) -> Tint? {
        guard let data else { return nil }
        let key = data.hashValue
        if let t = cache[key] { return t }
        guard let img = NSImage(data: data), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        // Thu về 8×8 rồi lấy trung bình từng nửa.
        let n = 8
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        func avg(_ rows: Range<Int>) -> Color {
            var r = 0.0, g = 0.0, b = 0.0, c = 0.0
            for y in rows { for x in 0..<n {
                let i = (y * n + x) * 4
                r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); c += 1
            } }
            let ns = NSColor(srgbRed: r / c / 255, green: g / c / 255, blue: b / c / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            ns.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            // Đậm màu hơn + đủ sáng để hiện trên nền đen, không chói.
            return Color(hue: h, saturation: min(1, s * 1.35 + 0.08), brightness: min(0.95, max(0.55, v * 1.2)))
        }
        let t = Tint(primary: avg(0..<n / 2), secondary: avg(n / 2..<n))
        cache[key] = t
        return t
    }
}

import SwiftUI

/// Đường viền NGOÀI của notch dưới dạng OPEN path (bỏ cạnh trên nối vào menu bar):
/// bắt đầu từ tai trên-trái, xuống cạnh trái, vòng đáy, lên cạnh phải, kết ở
/// tai trên-phải. Dùng cho hiệu ứng ánh sáng chạy dọc viền.
struct NotchOutline: Shape {
    var bottom: CGFloat
    var inverse: CGFloat

    func path(in rect: CGRect) -> Path {
        let ir = max(0, min(inverse, rect.width / 2 - 1))
        let br = max(0, min(bottom, rect.height - ir - 1, rect.width / 2 - ir - 1))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))               // tai trên-trái
        if ir > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.minX + ir, y: rect.minY + ir),
                           control: CGPoint(x: rect.minX + ir, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.minX + ir, y: rect.maxY - br))  // xuống cạnh trái
        p.addQuadCurve(to: CGPoint(x: rect.minX + ir + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ir - br, y: rect.maxY))  // đáy
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ir, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ir, y: rect.minY + ir))  // lên cạnh phải
        if ir > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                           control: CGPoint(x: rect.maxX - ir, y: rect.minY))
        }
        return p   // KHÔNG close, KHÔNG có cạnh trên
    }
}

/// Viền ngoài notch NHẤP NHÁY CHẬM (breathe) — báo hiệu shelf đang giữ file.
/// Chu kỳ ~5s (2.5s sáng lên, 2.5s mờ đi), lặp mãi. Gradient đỏ→tím + glow nhẹ.
/// Tôn trọng Reduce Motion (đứng yên ở mức sáng vừa).
struct NotchEdgePulse: View {
    var bottom: CGFloat
    var inverse: CGFloat
    var reduceMotion: Bool

    @State private var bright = false

    // Gradient đỏ → tím.
    private let grad = LinearGradient(
        colors: [Color(red: 1.0, green: 0.24, blue: 0.44),      // #FF3D71
                 Color(red: 0.886, green: 0.294, blue: 0.769),  // #E24BC4
                 Color(red: 0.706, green: 0.294, blue: 1.0)],    // #B44BFF
        startPoint: .leading, endPoint: .trailing)

    private var outline: some Shape { NotchOutline(bottom: bottom, inverse: inverse) }

    var body: some View {
        let op: Double = reduceMotion ? 0.55 : (bright ? 0.95 : 0.18)
        ZStack {
            // glow lan toả
            outline.stroke(grad, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .blur(radius: 5).opacity(op * 0.8)
            // nét chính
            outline.stroke(grad, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .opacity(op)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                bright = true
            }
        }
    }
}

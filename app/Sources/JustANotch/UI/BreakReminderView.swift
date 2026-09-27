import SwiftUI

/// Lời nhắc đứng dậy + uống nước, hiện gọn ở hai wing của notch: bé mèo pixel
/// (lấy từ logo mặt mèo của app) bên trái, chữ bên phải. Không bung panel.
struct BreakReminderView: View {
    @ObservedObject var vm: NotchViewModel
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Mèo + chữ đều ở wing trái (đồng bộ với Clawd / thông báo Claude).
            HStack(spacing: 10) {
                PixelCatSprite(reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                Text("Đứng dậy nào")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 3) {
                    Text("uống ngụm nước")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.42, green: 0.78, blue: 1.0))
                }
                }
                .lineLimit(1)
                .fixedSize()
            }
            .padding(.leading, 14)
            .frame(width: vm.leftReveal, alignment: .leading)
            .clipped()

            Color.clear.frame(width: vm.coreWidth)
            Color.clear.frame(width: vm.rightReveal)
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
    }
}

/// Bé mèo pixel: ngồi → đứng dậy → vươn vai → cầm cốc uống nước. Vẽ bằng
/// `Canvas` từ lưới ký tự nên nét sắc ở mọi độ phân giải, không cần file ảnh.
struct PixelCatSprite: View {
    let reduceMotion: Bool
    var pixel: CGFloat = 1
    @State private var start = Date()

    var body: some View {
        let size = CGSize(width: CGFloat(PixelCat.width) * pixel, height: CGFloat(PixelCat.height) * pixel)
        Group {
            if reduceMotion {
                PixelCanvas(frame: PixelCat.still, pixel: pixel)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / PixelCat.fps)) { ctx in
                    let i = Int(ctx.date.timeIntervalSince(start) * PixelCat.fps)
                    PixelCanvas(frame: PixelCat.frame(i), pixel: pixel)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { start = Date() }
    }
}

struct PixelCanvas: View {
    let frame: [String]
    let pixel: CGFloat
    var palette: [Character: Color] = PixelCat.palette

    var body: some View {
        Canvas { ctx, _ in
            // Gộp mọi ô cùng màu vào MỘT path rồi tô một lần — tô từng ô riêng lẻ sẽ
            // lộ đường kẻ lưới ở mép (khử răng cưa từng hình chữ nhật).
            var paths: [Character: Path] = [:]
            for (y, row) in frame.enumerated() {
                for (x, ch) in row.enumerated() where palette[ch] != nil {
                    paths[ch, default: Path()].addRect(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel,
                                                              width: pixel, height: pixel))
                }
            }
            for (ch, path) in paths { ctx.fill(path, with: .color(palette[ch]!)) }
        }
    }
}

/// Dữ liệu sprite (khung, bảng màu, kích thước) sinh bởi `app/scripts/gen_sprites.py`
/// → `SpriteData.swift`. Vòng lặp ~4s ở 12fps: ngồi → đứng dậy → vươn vai → uống nước.
enum PixelCat {
    static func frame(_ i: Int) -> [String] { loopFrames[loop[i % loop.count]] }
    static var still: [String] { loopFrames[loop[loop.count * 5 / 8]] }
}

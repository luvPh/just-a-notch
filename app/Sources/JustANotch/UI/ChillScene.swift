import SwiftUI
import AppKit

/// Cảnh "Clawd chill" ở giữa pill — đổi theo giờ trong ngày.
/// Sprite sheet @2x (mỗi khung 88×30 px = 44×15pt) nằm ở Resources/Chill,
/// sinh bởi `app/scripts/gen_chill_hd.py --export`.
enum ChillScene: String, CaseIterable {
    case coffee = "ca-phe", reading = "doc-sach", fishing = "cau-ca", campfire = "lua-trai", sleeping = "ngu"

    /// Kích thước khung trong sheet (px) và kích thước hiển thị (pt, TRƯỚC khi pill thu 75%).
    static let framePixels = (w: 114, h: 39)
    static let size = CGSize(width: 76, height: 26)
    static let fps = 12.0

    /// Lịch trong ngày: sáng cà phê ngắm mưa, trưa–chiều đọc sách, hoàng hôn câu cá,
    /// tối lửa trại, khuya đi ngủ.
    static func forHour(_ h: Int) -> ChillScene {
        switch h {
        case 6..<11:  return .coffee
        case 11..<17: return .reading
        case 17..<19: return .fishing
        case 19..<23: return .campfire
        default:      return .sleeping
        }
    }

    /// Các khung đã cắt sẵn (cache theo cảnh).
    @MainActor var frames: [CGImage] {
        if let f = Self.cache[self] { return f }
        // App bundle trước; chạy test/dev thì đọc thẳng từ app/Resources/Chill trong repo.
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Chill/\(rawValue).png")
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Resources/Chill/\(rawValue).png").standardized
        let url = [bundled, dev].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
        let fw = Self.framePixels.w, fh = sheet.height
        let f = (0..<(sheet.width / fw)).compactMap {
            sheet.cropping(to: CGRect(x: $0 * fw, y: 0, width: fw, height: fh))
        }
        Self.cache[self] = f
        return f
    }
    @MainActor private static var cache: [ChillScene: [CGImage]] = [:]
}

struct ChillSceneView: View {
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        // Kiểm tra giờ mỗi phút để đổi cảnh; khung hình chạy 12 fps.
        TimelineView(.periodic(from: start, by: reduceMotion ? 60 : 1.0 / ChillScene.fps)) { ctx in
            let scene = ChillScene.forHour(Calendar.current.component(.hour, from: ctx.date))
            let frames = scene.frames
            if !frames.isEmpty {
                let i = reduceMotion ? 0 : Int(ctx.date.timeIntervalSince(start) * ChillScene.fps) % frames.count
                Image(decorative: frames[i], scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .id(scene)
                    .transition(.opacity)
            }
        }
        .frame(width: ChillScene.size.width, height: ChillScene.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(.easeInOut(duration: 0.6), value: ChillScene.forHour(Calendar.current.component(.hour, from: Date())))
    }
}

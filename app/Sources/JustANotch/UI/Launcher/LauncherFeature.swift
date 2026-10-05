import SwiftUI

/// Các tính năng nhanh trong launcher (hover lâu trên notch). Thêm tính năng mới:
/// thêm một case + icon/tên/màu/kích thước, rồi route view ở `LauncherBody`.
enum LauncherFeature: String, CaseIterable, Identifiable {
    case calculator, gold, claude

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .calculator: return "plus.forwardslash.minus"
        case .gold:       return "chart.line.uptrend.xyaxis"
        case .claude:     return "sparkle"
        }
    }

    var title: String {
        switch self {
        case .calculator: return "Máy tính & tỷ giá"
        case .gold:       return "Giá vàng"
        case .claude:     return "Claude & Codex"
        }
    }

    /// Màu nhấn của icon (gradient từ trên-trái xuống dưới-phải).
    var tint: [Color] {
        switch self {
        case .calculator: return [Color(red: 1.0, green: 0.62, blue: 0.36), Color(red: 0.98, green: 0.36, blue: 0.55)]
        case .gold:       return [Color(red: 1.0, green: 0.86, blue: 0.42), Color(red: 0.86, green: 0.6, blue: 0.14)]
        case .claude:     return [Color(red: 0.93, green: 0.56, blue: 0.43), Color(red: 0.76, green: 0.36, blue: 0.24)]
        }
    }

    /// Bề ngang bề mặt khi tính năng mở.
    var width: CGFloat {
        switch self {
        case .calculator: return 340
        case .gold:       return 360
        case .claude:     return 360
        }
    }

    /// Chiều cao phần thân (dưới hàng wing) khi tính năng mở.
    var bodyHeight: CGFloat {
        switch self {
        case .calculator: return 122
        case .gold:       return 128
        case .claude:     return 140
        }
    }
}

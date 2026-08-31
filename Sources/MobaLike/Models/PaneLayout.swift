import Foundation

/// 分屏平铺布局：单屏 / 2 格 / 4 格（2×2）
enum PaneLayout: String, Codable, CaseIterable, Identifiable {
    case single
    case two
    case four

    var id: String { rawValue }

    /// 需要显示的分屏格数
    var paneCount: Int {
        switch self {
        case .single: return 1
        case .two: return 2
        case .four: return 4
        }
    }

    var shortLabel: String {
        switch self {
        case .single: return "1"
        case .two: return "2"
        case .four: return "4"
        }
    }
}

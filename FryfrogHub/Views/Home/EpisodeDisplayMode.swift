import SwiftUI

// MARK: - 分集展示模式

/// 分集展示方式：缩略图网格 / 数字方块 / 紧凑列表（选择持久记忆）
enum EpisodeDisplayMode: String, CaseIterable, Identifiable {
    case grid
    case numbers
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "缩略图"
        case .numbers: return "数字"
        case .list: return "列表"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .numbers: return "number.square"
        case .list: return "list.bullet"
        }
    }
}

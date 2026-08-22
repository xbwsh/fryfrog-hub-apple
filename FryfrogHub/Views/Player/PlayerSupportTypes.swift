import SwiftUI
import UIKit

/// 双轴滑动手势：水平=快进/快退，垂直=亮度/音量
enum GestureAxis {
    case seek
    case brightness
    case volume
}

/// 手势/硬件键反馈内容：音量与亮度用系统样式顶部胶囊（图标+进度条），seek/speed 用中央文本
enum HUDContent {
    case volume(Float)
    case brightness(CGFloat)
    case seek(String)
    case speed(Double)
}

/// 字幕菜单选项（id 前缀区分类型：off / builtin:<sid> / ext:<url>，kind 携带轨数据）
struct SubtitleOption: Identifiable {
    enum Kind {
        case off
        case builtin(SubtitleTrack)
        case external(SubtitleFile)
    }

    let id: String
    let label: String
    let kind: Kind
}

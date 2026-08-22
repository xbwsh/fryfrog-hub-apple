import SwiftUI

/// 单行歌词（含时间戳，用于同步滚动高亮）
struct LyricsLine: Identifiable {
    let id: Int
    let time: Double
    let text: String
}

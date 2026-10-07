import SwiftUI
import os

/// 播放器入口：统一使用 libmpv 内核
struct VideoPlayerView: View {
    let videoId: Int64
    var title: String = ""
    /// 后端返回的签名流地址（相对路径）；为空时回退到自行拼接的流地址
    var streamUrl: String? = nil
    /// 封面图 URL（用于锁屏/控制中心显示）
    var coverUrl: String? = nil

    private static let logger = Logger(subsystem: "com.fryfrog.hub", category: "player")

    init(videoId: Int64, title: String = "", streamUrl: String? = nil, coverUrl: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.streamUrl = streamUrl
        self.coverUrl = coverUrl
        MPVLog.log("player open videoId=\(videoId)")
        Self.logger.info("player open videoId=\(videoId, privacy: .public)")
    }

    var body: some View {
        MpvVideoPlayerView(videoId: videoId, title: title, streamUrl: streamUrl, coverUrl: coverUrl)
    }
}

#Preview {
    VideoPlayerView(videoId: 1, title: "预览")
}
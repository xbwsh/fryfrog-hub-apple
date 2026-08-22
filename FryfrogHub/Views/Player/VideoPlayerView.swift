import SwiftUI
import os

/// 播放器入口：根据设置选择 libmpv 或系统播放器内核
struct VideoPlayerView: View {
    let videoId: Int64
    var title: String = ""
    /// 后端返回的签名流地址（相对路径）；为空时回退到自行拼接的流地址
    var streamUrl: String? = nil

    private static let logger = Logger(subsystem: "com.fryfrog.hub", category: "player")

    init(videoId: Int64, title: String = "", streamUrl: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.streamUrl = streamUrl
        MPVLog.log("player open videoId=\(videoId) engine=\(PlayerSettings.shared.engine.rawValue)")
        Self.logger.info("player open videoId=\(videoId, privacy: .public) engine=\(PlayerSettings.shared.engine.rawValue, privacy: .public)")
    }

    var body: some View {
        if PlayerSettings.shared.engine == .mpv {
            MpvVideoPlayerView(videoId: videoId, title: title, streamUrl: streamUrl)
        } else {
            SystemVideoPlayerView(videoId: videoId, streamUrl: streamUrl)
        }
    }
}

#Preview {
    VideoPlayerView(videoId: 1, title: "预览")
}

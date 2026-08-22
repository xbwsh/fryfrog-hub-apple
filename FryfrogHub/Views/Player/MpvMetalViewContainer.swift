import SwiftUI

/// mpv 渲染视图的 SwiftUI 容器
/// T1-2：Metal 初始化失败时不再崩溃——回退黑色占位 UIView，并把错误经 onFailure 交给播放页提示
struct MpvMetalViewContainer: UIViewRepresentable {
    let player: MpvPlayer
    @Binding var videoSize: CGSize?
    var onFailure: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        guard let view = MpvMetalView(player: player, frame: .zero) else {
            // 延迟到下一 runloop 上报，避免视图构建期间修改 SwiftUI 状态
            DispatchQueue.main.async {
                onFailure("视频渲染初始化失败：当前设备 Metal 环境不可用")
            }
            return UIView()
        }
        view.startRendering()
        view.onSizeChange = { size in
            videoSize = size
        }
        // 尺寸事件可能在视图挂载前已触发，挂载时同步一次
        if player.videoWidth > 0, player.videoHeight > 0 {
            videoSize = CGSize(width: player.videoWidth, height: player.videoHeight)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

#Preview {
    VideoPlayerView(videoId: 1, title: "预览")
}

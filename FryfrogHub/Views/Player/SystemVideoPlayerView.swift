import SwiftUI
import AVFoundation
import AVKit

/// 系统播放器：模态全屏 AVPlayerViewController（原生控件 + Done 关闭），退出/切后台时上报观看进度
struct SystemVideoPlayerView: View {
    let videoId: Int64
    /// 后端返回的签名流地址（相对路径）；为空时回退到自行拼接的流地址
    var streamUrl: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var player: AVPlayer?
    @State private var prepared = false
    @State private var currentPosition: Double = 0
    @State private var currentDuration: Double = 0
    @State private var knownDuration: Double = 0
    @State private var saved = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    private let service = VideoService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                NativePlayerPresenter(player: player, onDismiss: { dismiss() }, onExit: { saveProgress() })
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("准备中…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .task { await prepare() }
        .onDisappear { saveProgress() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                saveProgress()
            }
        }
    }

    private func prepare() async {
        guard !prepared else { return }
        prepared = true

        await MainActor.run {
            MusicAudioPlayer.shared.pauseImmediately()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        // 续播：有进度且未看完时从上次位置开始
        var resume: Double = 0
        if let progress = await service.fetchProgress(id: videoId),
           let pos = progress.positionSeconds,
           pos > 5,
           progress.completed != true {
            let dur = progress.durationSeconds ?? 0
            if dur <= 0 || pos < dur - 30 {
                resume = pos
            }
        }

        // 优先拉取新鲜签名，避免列表缓存的 7 天签名因密钥轮转失效
        var freshStreamUrl: String? = streamUrl
        if let s = try? await service.freshStreamPath(id: videoId), !s.isEmpty {
            freshStreamUrl = s
        }
        var url = service.streamURL(id: videoId)
        if let freshStreamUrl, let resolved = ServerConnection.shared.imageURL(for: freshStreamUrl) {
            url = resolved
        } else if let streamUrl, let resolved = ServerConnection.shared.imageURL(for: streamUrl) {
            url = resolved
        }
        let headerFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"
        var options: [String: Any] = [:]
        if let token = await service.authToken() {
            options[headerFieldsKey] = ["Authorization": "Bearer \(token)"]
        }
        let asset = AVURLAsset(url: url, options: options)
        let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))

        // 后台加载真实时长（非 faststart 文件 currentItem.duration 加载前不可用）
        let durationTask = Task {
            if let dur = try? await asset.load(.duration), dur.isNumeric {
                let seconds = dur.seconds
                if seconds.isFinite, seconds > 0 {
                    knownDuration = seconds
                }
            }
        }
        if resume > 0 {
            _ = try? await asset.load(.duration)
            await newPlayer.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        _ = durationTask

        attachTimeObserver(to: newPlayer)
        // 播放由播放器视图挂载后触发，避免"先播放后挂载"导致黑屏
        player = newPlayer
        observePlaybackEnd()
    }

    // MARK: - 进度

    private func attachTimeObserver(to player: AVPlayer) {
        detachTimeObserver()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak player] time in
            guard player != nil else { return }
            currentPosition = time.seconds
            currentDuration = effectiveDuration
        }
    }

    private func detachTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    /// 时长不可用（未加载完/无穷）时回退到已确认的真实时长
    private var effectiveDuration: Double {
        if currentDuration.isFinite, currentDuration > 0 {
            return currentDuration
        }
        return knownDuration
    }

    private func observePlaybackEnd() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [self] _ in
            guard let player = self.player else { return }
            let duration = player.currentItem?.duration.seconds ?? 0
            self.currentPosition = duration
            self.currentDuration = duration
            self.saveProgress()
        }
    }

    /// 退出播放器时上报播放位置（服务端自动判定是否看完）
    private func saveProgress() {
        guard !saved else { return }
        saved = true
        detachTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        let position = currentPosition
        let duration = effectiveDuration
        player?.pause()
        player = nil
        let id = videoId
        Task {
            await service.updatePosition(id: id, position: position, duration: duration)
        }
    }
}

#Preview {
    SystemVideoPlayerView(videoId: 1)
}

/// 从窗口顶层视图控制器模态全屏展示 AVPlayerViewController：
/// 原生播放控件 + 原生 Done 关闭按钮，关闭后回调给 SwiftUI 层
private struct NativePlayerPresenter: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: () -> Void
    /// 播放器被关闭时立即上报进度（不依赖 cover 的 onDisappear 链）
    var onExit: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onExit = onExit
        guard !context.coordinator.didPresent else { return }
        context.coordinator.didPresent = true
        DispatchQueue.main.async {
            context.coordinator.present(player: player)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var didPresent = false
        var didNotifyDismiss = false
        var onDismiss: (() -> Void)?
        var onExit: (() -> Void)?
        weak var playerVC: PlayerViewController?

        /// 从窗口顶层控制器弹出，保证 presenter 一定在视图层级中（避免 present 静默失败导致黑屏）
        func present(player: AVPlayer) {
            guard playerVC == nil else { return }
            guard let top = topViewController() else {
                player.play()
                return
            }
            let vc = PlayerViewController()
            vc.player = player
            vc.showsPlaybackControls = true
            playerVC = vc
            vc.onDismiss = { [weak self] in
                self?.notifyDismissed()
            }
            top.present(vc, animated: true) { [weak self] in
                vc.presentationController?.delegate = self
                // 挂载完成后再开始播放
                player.play()
            }
        }

        /// 兜底路径：若 Done 关闭未走 viewDidDisappear 检测，presentationController 回调也能触发
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            notifyDismissed()
        }

        private func notifyDismissed() {
            guard !didNotifyDismiss else { return }
            didNotifyDismiss = true
            onExit?()
            onDismiss?()
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
                  let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                      ?? windowScene.windows.first?.rootViewController else {
                return nil
            }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }
    }
}

/// 子类化以便可靠感知模态关闭：Done 按钮导致本页被 dismiss 时，viewDidDisappear 必然回调
private final class PlayerViewController: AVPlayerViewController {
    var onDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismiss?()
        }
    }
}

import SwiftUI
import AVFoundation
import MediaPlayer
import QuartzCore

/// 视频播放器：libmpv 内核 + 自绘控件（Metal 显示），观感模仿系统播放器
/// （点击切换控件显示/隐藏、播放中无操作自动隐藏、上下渐变压暗），退出/暂停时上报观看进度
struct MpvVideoPlayerView: View {
    let videoId: Int64
    var title: String = ""
    /// 后端返回的签名流地址（相对路径）；为空时回退到自行拼接的流地址
    var streamUrl: String? = nil
    /// 封面图 URL（用于锁屏/控制中心显示）
    var coverUrl: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var player: MpvPlayer?
    @State private var prepared = false
    @State private var isReady = false
    @State private var isPlaying = false
    @State private var currentPosition: Double = 0
    @State private var currentDuration: Double = 0
    // 位置节流：mpv 的 time-pos 观察按视频帧率回调（~60fps），直接写 @State 会让整个
    // body 每帧重算（信息面板/进度条/金属渲染合成），滚动时帧率低；降到 ~4Hz 足够
    @State private var lastPositionEmitTime: TimeInterval = 0
    // 锁屏/控制中心信息节流：位置 4Hz 刷新，但 MPNowPlayingInfoCenter 跨进程写入降到 1Hz
    @State private var lastNowPlayingUpdate: TimeInterval = 0
    @State private var cacheDuration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var saved = false
    /// 播放到结尾（仅上报进度+展示完成浮层，不销毁播放器）
    @State private var isFinished = false
    /// 重新播放时跳过一次续播 seek（否则重播会跳回首次打开的续播位置）
    @State private var suppressResumeSeek = false
    @State private var errorMessage: String?
    @State private var checkpointTimer: Timer?
    @State private var videoSize: CGSize?
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var subtitleOptions: [SubtitleOption] = []
    @State private var selectedSubtitleID: String?
    @State private var showSubtitleMenu = false
    @State private var showInfoMenu = false
    @State private var playbackInfo: PlaybackInfo?
    @State private var playbackSpeed: Double = 1.0
    @State private var showSpeedMenu = false
    // 手势：滑动起点基准值 + 系统音量滑杆
    @State private var dragStartBrightness: CGFloat?
    @State private var dragStartVolume: Float?
    @State private var volumeSlider: UISlider?
    // 双轴手势：轴判定 + seek 状态 + 反馈
    @State private var gestureAxis: GestureAxis?
    @State private var seekStartPosition: Double?
    @State private var lastSeekTranslation: CGFloat = 0
    // 长按 2x：按住期间进入加速，松手恢复；进入前记住原倍速用于恢复
    @State private var isTurboActive = false
    @State private var speedBeforeLongPress: Double?
    // T4-1：上一次单击的时间戳（单调时钟），用于自判双击
    @State private var lastTapAt: TimeInterval = 0
    @State private var hudContent: HUDContent?
    @State private var hudDismissTask: Task<Void, Never>?
    // 硬件音量键轮询兜底（私有通知 AVSystemController 在部分系统版本不触发）
    @State private var volumePollTask: Task<Void, Never>?
    @State private var lastPolledVolume: Float = -1
    @State private var artworkImage: UIImage?

    private let service = VideoService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                if let videoSize, videoSize.height > 0 {
                    MpvMetalViewContainer(player: player, videoSize: $videoSize, controlsVisible: controlsVisible, onFailure: handleRenderFailure)
                        .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
                        .ignoresSafeArea()
                } else {
                    // 视频尺寸未就绪前先铺满黑屏
                    MpvMetalViewContainer(player: player, videoSize: $videoSize, controlsVisible: controlsVisible, onFailure: handleRenderFailure)
                        .ignoresSafeArea()
                }
            } else {
                ProgressView("准备中…")
                    .tint(.white)
            }

            // 准备中覆盖层：播放器实例化后、首帧/尺寸就绪前居中提示
            if !isReady, errorMessage == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("准备中…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }

            // 顶部/底部渐变遮罩：与黑背景同级放入 ZStack，ignoresSafeArea 确保贴满屏幕物理边缘
            // （overlay 内容在横屏下可能受安全区限制导致边缘缺口，放 ZStack 内最可靠）
            if controlsVisible {
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if controlsVisible {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // 手势层：双击暂停/播放，单击切换控件，左侧上下滑调亮度、右侧上下滑调音量，长按切 2x
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    // T4-1：时间戳自判替代 TapGesture(count:2).exclusively 仲裁——
                    // 单击立即执行 toggleControls（原方案被双击判定窗口阻塞 ~300ms）；
                    // 窗口内出现第二击则改判为双击执行 togglePlay。
                    // 副作用（可接受）：双击时第一次的控件切换已生效，与主流播放器
                    // "双击暂停且控件可见"的行为一致。拖动/长按走 simultaneous 手势不受影响。
                    TapGesture().onEnded { handlePlayAreaTap() }
                )
                .simultaneousGesture(adjustGesture)
                .simultaneousGesture(
                    // 长按屏幕 0.5s 进入 2x，松手恢复原倍速。
                    // 用 sequenced：长按成功后才衔接拖动手势；拖动开始=已满 2s 进入加速，
                    // 拖动结束(松手)=恢复原倍速。避免 updating 在按下瞬间即触发的问题。
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second = value, !isTurboActive {
                                startTurboSpeed()
                            }
                        }
                        .onEnded { value in
                            if case .second = value {
                                endTurboSpeed()
                            }
                        }
                )
                .ignoresSafeArea()

            // 字幕选择面板（带半透明遮罩与选中勾选标记）
            if showSubtitleMenu {
                subtitleMenuOverlay
                    .transition(.opacity)
            }

            // 视频信息面板
            if showInfoMenu {
                infoMenuOverlay
                    .transition(.opacity)
            }

            // 倍速选择面板
            if showSpeedMenu {
                speedMenuOverlay
                    .transition(.opacity)
            }

            // 反馈 HUD：音量/亮度=系统样式顶部胶囊，快进快退=中央目标时间
            if let hudContent {
                switch hudContent {
                case .volume(let v):
                    systemCapsule(icon: volumeIcon(v), progress: CGFloat(v))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .safeAreaPadding(.top, 6)
                        .transition(.opacity)
                case .brightness(let b):
                    systemCapsule(icon: "sun.max.fill", progress: b)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .safeAreaPadding(.top, 6)
                        .transition(.opacity)
                case .seek(let text):
                    Text(text)
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                case .speed(let rate):
                    Text(Self.speedLabel(rate))
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .top) {
            // 顶部栏：控件避开安全区（渐变已在 ZStack 内贴边）
            if controlsVisible {
                topBar
                    .safeAreaPadding(.top, 12)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // 控制栏：不设置底部 padding，直接贴屏幕底（渐变已在 ZStack 内贴边）
            if controlsVisible {
                controlBar
                    .transition(.opacity)
            }
        }
        .overlay {
            if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)
            }
        }
        .overlay {
            // 播放完成浮层：原实现走到 saveProgress()（销毁播放器）导致画面永久"准备中…"
            if isFinished {
                VStack(spacing: 16) {
                    Text("播放完毕")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                    HStack(spacing: 28) {
                        Button {
                            replayFromStart()
                        } label: {
                            Label("重新播放", systemImage: "arrow.counterclockwise")
                        }
                        Button {
                            // 退出清理统一走 onDisappear → saveProgress()
                            dismiss()
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
        .statusBarHidden(!controlsVisible)
        .background(
            // 隐藏的 MPVolumeView，抓取内部滑杆用于手势调系统音量
            HiddenVolumeView { slider in
                volumeSlider = slider
            }
        )
        .onReceive(
            // 硬件音量键通知（私有通知名，系统稳定存在；AVAudioSession 无公开 volumeDidChangeNotification）
            NotificationCenter.default.publisher(for: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"))
        ) { _ in
            // 硬件音量键：状态栏隐藏时系统 HUD 不显示，用自绘系统样式胶囊替代
            let volume = AVAudioSession.sharedInstance().outputVolume
            hudContent = .volume(volume)
            scheduleHUDDismiss()
        }
        .task { await prepare() }
        .task { startVolumePolling() }
        .onAppear {
            // 播放器为纯黑背景，强制深色外观保证状态栏浅色文字
            AppAppearance.applyWindowInterfaceStyle(.dark)
        }
        .onDisappear {
            saveProgress()
            // 退出播放器还原用户主题对应的窗口外观
            AppAppearance.applyWindowInterfaceStyle(AppAppearance.style(for: ThemeSettings.shared.mode))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // 进后台仅上报进度（防杀进程丢进度），播放器保持存活以支持
                // 后台音频/锁屏控制；真正销毁在 onDisappear 的 saveProgress()。
                // （原实现在此直接销毁播放器且无回前台重建路径 → 切后台回来永久"准备中…"）
                checkpointSave()
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                scheduleAutoHide()
            } else {
                // 暂停时保持控件常显
                controlsHideTask?.cancel()
            }
        }
    }

    // MARK: - 控件显示/隐藏（模仿系统播放器）

    /// 屏幕手势：左右滑=快进/快退，左半区上下滑=亮度，右半区上下滑=音量
    /// （首次拖动按主导方向判定轴，之后固定）
    private var adjustGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if gestureAxis == nil {
                    if abs(dx) > abs(dy) {
                        gestureAxis = .seek
                        seekStartPosition = player?.position ?? currentPosition
                        lastSeekTranslation = dx
                    } else {
                        let isLeft = value.startLocation.x < UIScreen.main.bounds.width / 2
                        gestureAxis = isLeft ? .brightness : .volume
                        if dragStartBrightness == nil { dragStartBrightness = UIScreen.main.brightness }
                        if dragStartVolume == nil {
                            dragStartVolume = volumeSlider?.value ?? AVAudioSession.sharedInstance().outputVolume
                        }
                    }
                }

                switch gestureAxis {
                case .seek:
                    // 节流：位移累计超 8pt 才 seek，避免高频 seek 卡顿
                    guard abs(dx - lastSeekTranslation) > 8 else { break }
                    lastSeekTranslation = dx
                    let delta = Double(dx) / 300 * 60  // 滑 300pt ≈ 快进/快退 60 秒
                    if let start = seekStartPosition {
                        let target = min(max(start + delta, 0), sliderUpperBound)
                        player?.seek(to: target)
                        hudContent = .seek(timeText(target))  // 显示快进/快退后的目标时间
                    }
                case .brightness:
                    let delta = Double(-dy) / 300
                    if let start = dragStartBrightness {
                        let value = min(max(start + delta, 0.05), 1)
                        UIScreen.main.brightness = value
                        hudContent = .brightness(value)
                    }
                case .volume:
                    let delta = Double(-dy) / 300
                    if dragStartVolume == nil {
                        // 隐藏 MPVolumeView 的 slider.value 初始为 0（未同步系统音量），
                        // 必须用 AVAudioSession.outputVolume 读真实系统音量
                        dragStartVolume = currentSystemVolume
                    }
                    if let start = dragStartVolume {
                        let value = min(max(start + Float(delta), 0), 1)
                        setSystemVolume(value)
                        hudContent = .volume(value)
                    }
                case nil:
                    break
                }
            }
            .onEnded { _ in
                gestureAxis = nil
                seekStartPosition = nil
                lastSeekTranslation = 0
                dragStartBrightness = nil
                dragStartVolume = nil
                withAnimation(.easeOut(duration: 0.15)) { hudContent = nil }
            }
    }

    /// 当前系统音量：优先 AVAudioSession（真实值）；MPVolumeView slider.value 初始为 0 不可靠
    private var currentSystemVolume: Float {
        let output = AVAudioSession.sharedInstance().outputVolume
        if output > 0 { return output }
        return volumeSlider?.value ?? output
    }

    /// 明确设置系统全局音量（0~1）：
    /// 首选 AVAudioSession 的 setOutputVolume:（未公开方法，直接控制系统音量）；
    /// MPVolumeView slider 作兜底
    private func setSystemVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        let session = AVAudioSession.sharedInstance()
        let selector = NSSelectorFromString("set" + "OutputVolume:")
        if session.responds(to: selector) {
            session.perform(selector, with: NSNumber(value: clamped))
        }
        volumeSlider?.value = clamped
    }

    private func toggleControls() {
        if controlsVisible {
            controlsHideTask?.cancel()
            withAnimation(.easeIn(duration: 0.15)) { controlsVisible = false }
        } else {
            showControls()
        }
    }

    /// 双击判定窗口（对齐系统双击手感 ~0.3s）
    private static let doubleTapWindow: TimeInterval = 0.3

    /// T4-1：单击/双击时间戳自判——首击立即切换控件，窗口内第二击改判为播放/暂停
    private func handlePlayAreaTap() {
        let now = CACurrentMediaTime()
        if now - lastTapAt <= Self.doubleTapWindow {
            // 第二击：按双击处理，重置计时避免三击被误判为两组双击
            lastTapAt = 0
            togglePlay()
        } else {
            lastTapAt = now
            toggleControls()
        }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true }
        scheduleAutoHide()
    }

    /// 播放中 4 秒无操作后自动隐藏控件
    private func scheduleAutoHide() {
        controlsHideTask?.cancel()
        guard isPlaying else { return }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { controlsVisible = false }
        }
    }

    /// 硬件音量键触发的 HUD 1.5 秒后自动消失
    private func scheduleHUDDismiss() {
        hudDismissTask?.cancel()
        hudDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { hudContent = nil }
        }
    }

    /// 轮询检测硬件音量键变化（1s 间隔），私有通知不可靠时兜底显示胶囊
    /// 1s 足以覆盖按键节奏，同时避免播放期间每秒 3 次的空转唤醒
    private func startVolumePolling() {
        volumePollTask?.cancel()
        lastPolledVolume = AVAudioSession.sharedInstance().outputVolume
        volumePollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                let current = AVAudioSession.sharedInstance().outputVolume
                if abs(current - lastPolledVolume) > 0.01 {
                    lastPolledVolume = current
                    // 滑动调音量时手势已在更新 HUD，轮询只兜底硬件键场景
                    if gestureAxis == nil {
                        hudContent = .volume(current)
                        scheduleHUDDismiss()
                    }
                }
            }
        }
    }

    private func stopVolumePolling() {
        volumePollTask?.cancel()
        volumePollTask = nil
    }

    /// 系统样式顶部胶囊：图标 + 细进度条（iOS 26+ 液态玻璃，低版本回退毛玻璃）
    private func systemCapsule(icon: String, progress: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 90, height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: 90 * min(max(progress, 0), 1), height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
    }

    /// 音量图标随大小切换（静音/低/高）
    private func volumeIcon(_ volume: Float) -> String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    // MARK: - 视频信息面板

    /// 视频信息面板（左上角弹出，内容自适应高度，无需滚动；遮罩点击关闭）
    private var infoMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showInfoMenu = false }
                    scheduleAutoHide()
                }

            infoMenuPanel
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private var infoMenuPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("视频信息")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showInfoMenu = false }
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(.white.opacity(0.15))

            VStack(spacing: 0) {
                // 播放类型与缓冲
                infoRow("播放类型", playTypeText)
                infoRow("缓冲时长", bufferedText)

                // 视频信息
                sectionHeader("视频")
                infoRow("分辨率", resolutionText)
                infoRow("编码器", codecText(playbackInfo?.videoCodec))
                infoRow("动态范围", dynamicRangeText)
                infoRow("帧率", fpsText)

                // 音频信息
                sectionHeader("音频")
                infoRow("编码器", codecText(playbackInfo?.audioCodec))
                infoRow("声道", playbackInfo?.audioChannels)
                infoRow("采样率", sampleRateText(playbackInfo?.audioSampleRate))

                // 媒体源信息
                sectionHeader("媒体源")
                infoRow("封装容器", playbackInfo?.containerFormat)
            }
        }
        .frame(width: 320)
        // 液态玻璃面板背景
        .background { glassPanelBackground(cornerRadius: 18) }
        .padding(.top, 16)
        .padding(.leading, 16)
    }

    /// 信息分组标题（小号次级色，组间分隔）
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 16)
            Text(value ?? "—")
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private var resolutionText: String? {
        guard let info = playbackInfo, info.width > 0, info.height > 0 else { return nil }
        return "\(info.width) × \(info.height)"
    }

    private var fpsText: String? {
        guard let fps = playbackInfo?.fps, fps.isFinite, fps > 0 else { return nil }
        return String(format: "%.2f", fps)
    }



    private func sampleRateText(_ rate: Int64?) -> String? {
        guard let rate, rate > 0 else { return nil }
        if rate >= 1000 {
            return rate % 1000 == 0
                ? "\(rate / 1000) kHz"
                : String(format: "%.1f kHz", Double(rate) / 1000)
        }
        return "\(rate) Hz"
    }

    private var subtitleCountText: String? {
        guard let count = playbackInfo?.subtitleTrackCount else { return nil }
        return "\(count) 条"
    }

    /// 播放类型：mpv 直连播放
    private var playTypeText: String {
        return "直接播放"
    }

    /// 动态范围显示
    private var dynamicRangeText: String? {
        guard let info = playbackInfo, let dr = info.dynamicRange else { return nil }
        return dr
    }

    /// 已缓冲时长（demuxer-cache-duration）
    private var bufferedText: String? {
        guard let duration = playbackInfo?.cacheDuration, duration.isFinite, duration > 0 else { return nil }
        if duration >= 60 {
            return String(format: "%.1f 分钟", duration / 60)
        }
        return String(format: "%.0f 秒", duration)
    }

    /// 编码名显示：mpv 返回 "hevc (Main 10)" / "hevc (null)" / "hevc ()" 等形式，
    /// profile 缺失（NULL 或空）时去掉多余括号，只保留编码名
    private func codecText(_ codec: String?) -> String? {
        guard let codec else { return nil }
        // 去掉任意尾随括号组（兼容空括号、null、hvc1 标记、全角括号），只留编码器名
        let cleaned = codec
            .replacingOccurrences(of: #"\s*[（(][^（()）]*[）)]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }



    // MARK: - 字幕选择面板

    /// 字幕选择面板（右侧垂直居中弹出，遮罩 + 选项列表，选中项带勾选）
    private var subtitleMenuOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showSubtitleMenu = false }
                    scheduleAutoHide()
                }

            subtitleMenuPanel
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var subtitleMenuPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("字幕")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSubtitleMenu = false }
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(subtitleOptions) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showSubtitleMenu = false }
                            applySubtitle(option)
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                if selectedSubtitleID == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        if option.id != subtitleOptions.last?.id {
                            Divider().overlay(.white.opacity(0.15))
                        }
                    }
                }
            }
            .frame(maxHeight: 230)
        }
        .frame(width: 250)
        .background { glassPanelBackground(cornerRadius: 16) }
        .padding(.trailing, 16)
    }

    // MARK: - 倍速

    /// 可选倍速档位
    static let speedOptions: [Double] = [0.5, 1.0, 2.0, 3.0]

    /// 倍速显示文案：1.0 → "1x"，1.5 → "1.5x"
    static func speedLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? String(format: "%.0fx", rate) : String(format: "%.2fx", rate)
    }

    /// 倍速选择面板（右侧垂直居中弹出，遮罩 + 选项列表，选中项带勾选）
    private var speedMenuOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showSpeedMenu = false }
                    scheduleAutoHide()
                }

            speedMenuPanel
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var speedMenuPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("倍速")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSpeedMenu = false }
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Self.speedOptions, id: \.self) { rate in
                    Button {
                        applySpeed(rate)
                    } label: {
                        HStack(spacing: 8) {
                            Text(Self.speedLabel(rate))
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer()
                            if abs(playbackSpeed - rate) < 0.001 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    if rate != Self.speedOptions.last {
                        Divider().overlay(.white.opacity(0.15))
                    }
                }
            }
        }
        .frame(width: 250)
        .background { glassPanelBackground(cornerRadius: 16) }
        .padding(.trailing, 16)
    }

    private func applySpeed(_ rate: Double) {
        playbackSpeed = rate
        player?.setSpeed(rate)
        withAnimation(.easeOut(duration: 0.2)) { showSpeedMenu = false }
        scheduleAutoHide()
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background { circleGlassBackground() }
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // 字幕按钮（有字幕轨/外挂字幕时显示）
            if !subtitleOptions.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSubtitleMenu = true }
                    controlsHideTask?.cancel()
                    withAnimation { controlsVisible = true }
                } label: {
                    Image(systemName: hasCustomSubtitle ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hasCustomSubtitle ? .white : .white.opacity(0.65))
                        .frame(width: 36, height: 36)
                        .background { circleGlassBackground() }
                }
            }

            // 倍速按钮（非 1x 时常显白，提示当前处于变速状态）
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showSpeedMenu = true }
                controlsHideTask?.cancel()
                withAnimation { controlsVisible = true }
            } label: {
                Text(Self.speedLabel(playbackSpeed))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(playbackSpeed == 1.0 ? .white.opacity(0.65) : .white)
                    .frame(width: 36, height: 36)
                    .background { circleGlassBackground() }
            }

            // 视频信息按钮
            Button {
                playbackInfo = player?.fetchPlaybackInfo()
                withAnimation(.easeOut(duration: 0.2)) { showInfoMenu = true }
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background { circleGlassBackground() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// 液态玻璃圆形背景（iOS 26+ 液态玻璃，低版本回退毛玻璃）
    @ViewBuilder
    private func circleGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            Circle().fill(.clear).glassEffect(.regular, in: .circle)
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }

    /// 液态玻璃面板背景（iOS 26+），低版本回退深色面板
    @ViewBuilder
    private func glassPanelBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black.opacity(0.92))
        }
    }

    // MARK: - 底部控制栏

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
            }
            .tint(.white)

            Text(timeText(currentPosition))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 48, alignment: .leading)

            ZStack(alignment: .leading) {
                FlatSlider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : min(currentPosition, sliderUpperBound) },
                        set: { scrubValue = $0 }
                    ),
                    range: 0...sliderUpperBound,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            // 拖动中不自动隐藏
                            controlsHideTask?.cancel()
                        } else {
                            player?.seek(to: scrubValue)
                            scheduleAutoHide()
                        }
                    }
                )

                // 已缓冲区域指示（位于滑杆轨道之下，宽度=缓冲占比）
                GeometryReader { geo in
                    let total = max(sliderUpperBound, 1)
                    let ratio = min(cacheDuration / total, 1)
                    if ratio > 0.01 {
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(width: max(0, geo.size.width * ratio), height: 4)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 44)

            Text(timeText(sliderUpperBound))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { controlBarGlassBackground() }
        .padding(.horizontal, 12)
    }

    /// 底部控制栏液态玻璃背景
    @ViewBuilder
    private func controlBarGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - 字幕

    /// 是否选中了具体的字幕轨（非 关闭）
    private var hasCustomSubtitle: Bool {
        guard let selectedSubtitleID else { return false }
        return selectedSubtitleID != "off"
    }

    /// 拉取内置字幕轨 + 后端外挂字幕，组装菜单选项并恢复上次选择
    private func loadSubtitles() async {
        guard let player else { return }
        let builtin = player.fetchSubtitleTracks()
        let external = await service.fetchSubtitles(id: videoId)

        var options = [
            SubtitleOption(id: "off", label: "关闭", kind: .off),
        ]
        options += builtin.map { track in
            // title 比 lang 更具体（如"简体"/"繁体"），优先显示；lang 代码翻译后兜底
            let name = track.title ?? Self.languageName(track.lang) ?? "轨道 \(track.id)"
            return SubtitleOption(id: "builtin:\(track.id)", label: "内置 · \(name)", kind: .builtin(track))
        }
        options += external.map { file in
            let lang = file.language.flatMap(Self.languageName).map { " · \($0)" } ?? ""
            return SubtitleOption(id: "ext:\(file.url ?? file.filename)", label: "外挂 · \(file.filename)\(lang)", kind: .external(file))
        }
        subtitleOptions = options

        restoreSubtitlePreference(builtin: builtin, external: external)
    }

    /// 恢复上次字幕选择；无匹配时默认选第一条内置轨
    private func restoreSubtitlePreference(builtin: [SubtitleTrack], external: [SubtitleFile]) {
        var target: SubtitleOption?
        if let pref = PlayerSettings.shared.subtitlePreference {
            switch pref.kind {
            case .off:
                target = subtitleOptions.first { option in
                    if case .off = option.kind { return true }
                    return false
                }
            case .builtin:
                if let title = pref.title,
                   let t = builtin.first(where: { $0.title == title }) {
                    target = option(forBuiltin: t)
                } else if let lang = pref.lang,
                          let t = builtin.first(where: { $0.lang == lang }) {
                    target = option(forBuiltin: t)
                }
            case .external:
                if let filename = pref.filename,
                   let f = external.first(where: { $0.filename == filename }),
                   let url = f.url {
                    target = subtitleOptions.first { option in
                        if case .external(let file) = option.kind { return file.url == url }
                        return false
                    }
                }
            }
        }
        // 无偏好或匹配失败：默认第一条内置轨（mpv 的 auto 不会自动选中带语言标签的轨）
        if target == nil, let first = builtin.first {
            target = option(forBuiltin: first)
        }
        if let target {
            applySubtitleSelection(target)
        } else {
            selectedSubtitleID = "off"
        }
    }

    private func option(forBuiltin track: SubtitleTrack) -> SubtitleOption? {
        subtitleOptions.first { option in
            if case .builtin(let t) = option.kind { return t.id == track.id }
            return false
        }
    }

    private func applySubtitle(_ option: SubtitleOption) {
        applySubtitleSelection(option)
        saveSubtitlePreference(option)
        scheduleAutoHide()
    }

    private func applySubtitleSelection(_ option: SubtitleOption) {
        selectedSubtitleID = option.id
        switch option.kind {
        case .off:
            player?.selectSubtitle(.off)
        case .builtin(let track):
            player?.selectSubtitle(.builtin(sid: track.id))
        case .external(let file):
            if let url = file.url {
                player?.selectSubtitle(.external(url: url))
            }
        }
    }

    private func saveSubtitlePreference(_ option: SubtitleOption) {
        switch option.kind {
        case .off:
            PlayerSettings.shared.subtitlePreference = SubtitlePreference(kind: .off)
        case .builtin(let track):
            PlayerSettings.shared.subtitlePreference = SubtitlePreference(
                kind: .builtin,
                title: track.title,
                lang: track.lang,
                filename: nil
            )
        case .external(let file):
            PlayerSettings.shared.subtitlePreference = SubtitlePreference(
                kind: .external,
                title: nil,
                lang: nil,
                filename: file.filename
            )
        }
    }

    /// 语言代码 → 中文名（保留 zh-Hans/zh-Hant 的简繁区分；chi/zho 无简繁信息返回"中文"）
    private static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        switch code.lowercased() {
        case "zh-hans", "zh-cn", "zh-sg": return "简体中文"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo": return "繁体中文"
        case "chi", "zho", "zh": return "中文"
        case "eng": return "英语"
        case "jpn", "ja": return "日语"
        case "kor", "ko": return "韩语"
        case "fra", "fre", "fr": return "法语"
        case "deu", "ger", "de": return "德语"
        case "spa", "es": return "西班牙语"
        case "rus", "ru": return "俄语"
        case "tha", "th": return "泰语"
        case "vie", "vi": return "越南语"
        case "ind", "id": return "印尼语"
        case "ara": return "阿拉伯语"
        case "por": return "葡萄牙语"
        case "und": return nil
        default: return code
        }
    }

    /// 进度条上限：时长不可用（未就绪/解析失败）时回退为 1，避免 NaN/无穷区间卡死
    private var sliderUpperBound: Double {
        currentDuration.isFinite && currentDuration > 0 ? currentDuration : 1
    }

    private func togglePlay() {
        guard let player else { return }
        isPlaying = player.togglePause()
        checkpointSave()
        updateNowPlayingInfo()
    }

    /// 长按屏幕满 0.5s 进入 2x：记住原倍速，切到 2x，中央 HUD 持续显示直到松手
    private func startTurboSpeed() {
        guard let player else { return }
        isTurboActive = true
        speedBeforeLongPress = playbackSpeed
        playbackSpeed = 2.0
        player.setSpeed(2.0)
        hudDismissTask?.cancel()
        hudContent = .speed(2.0)
        updateNowPlayingInfo()
        // 按住期间 HUD 常显，不自动消失；松手时由 endTurboSpeed 负责消失
    }

    /// 松手恢复长按前的倍速（若非 1x 显示恢复后倍速提示，1x 则直接消失）
    private func endTurboSpeed() {
        guard isTurboActive else {
            hudContent = nil
            return
        }
        isTurboActive = false
        guard let restore = speedBeforeLongPress else {
            hudContent = nil
            updateNowPlayingInfo()
            return
        }
        speedBeforeLongPress = nil
        playbackSpeed = restore
        player?.setSpeed(restore)
        if restore != 1.0 {
            hudContent = .speed(restore)
            scheduleHUDDismiss()
        } else {
            hudContent = nil
        }
        updateNowPlayingInfo()
        if isPlaying {
            scheduleAutoHide()
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - 生命周期

    private func prepare() async {
        guard !prepared else { return }
        prepared = true
        isReady = false

        // 音乐与视频抢占同一 AVAudioSession(.playback)：有音乐在播时 mpv 的 audiounit 会被静音/甚至阻塞视频渲染（有画无声或有声无画）
        // 必须先暂停音乐并释放其会话，再激活视频会话
        await MainActor.run {
            MusicAudioPlayer.shared.pauseImmediately()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        // mpv 的 AudioUnit 输出需要会话处于激活状态
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        // 并行：进度和 token 同时请求，减少等待时间
        let progressTask = Task { await service.fetchProgress(id: videoId) }
        let token = await service.authToken()

        var headers: [String: String] = [:]
        if let token {
            headers["Authorization"] = "Bearer \(token)"
        }

        // 续播：有进度且未看完时从上次位置开始
        var resume: Double = 0
        if let progress = await progressTask.value,
           let pos = progress.positionSeconds,
           pos > 5,
           progress.completed != true {
            let dur = progress.durationSeconds ?? 0
            if dur <= 0 || pos < dur - 30 {
                resume = pos
            }
        }

        // 上面存在多个 await：期间视图可能已被关掉（.task 取消，onDisappear 已执行
        // saveProgress 置 saved）。此处不校验会创建出无人 shutdown 的孤儿播放器
        // （事件线程永久轮询、退出后音频继续外放）
        if Task.isCancelled || saved {
            return
        }

        let newPlayer = MpvPlayer()
        newPlayer.onPosition = { [self] position in
            // 节流：mpv 按帧回调 time-pos，若逐帧写 @State 则整个 body 每帧重算，
            // 叠加实时金属视频时滚动/交互帧率低。0.25s 间隔足够进度显示
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastPositionEmitTime >= 0.25 else { return }
            lastPositionEmitTime = now
            currentPosition = position
            // 锁屏进度由 playbackRate 自动推进，不必随每帧位置更新写入
            if now - lastNowPlayingUpdate >= 1.0 {
                lastNowPlayingUpdate = now
                updateNowPlayingInfo()
            }
        }
        newPlayer.onDuration = { duration in
            currentDuration = duration
            updateNowPlayingInfo()
        }
        newPlayer.onCacheDuration = { buffered in
            cacheDuration = buffered
        }
        newPlayer.onPauseChanged = { paused in
            isPlaying = !paused
            if paused { checkpointSave() }
            updateNowPlayingInfo()
        }
        newPlayer.onEndReached = {
            handlePlaybackFinished()
        }
        newPlayer.onError = { message in
            errorMessage = message
        }
        newPlayer.onReady = {
            // 文件加载完成（track-list 就绪）后拉取字幕轨与外挂字幕列表
            Task { @MainActor in
                isReady = true
                await self.loadSubtitles()
                if let coverUrl, let url = ServerConnection.shared.imageURL(for: coverUrl) {
                    let image = try? await AuthImageLoader.shared.loadScaled(url: url)
                    if let image { self.artworkImage = image }
                    updateNowPlayingInfo()
                }
                // 续播：文件就绪后 seek 到记录位置（比 create 时的 start 属性更可靠）
                // 重新播放（suppressResumeSeek）时跳过，从头开始
                if resume > 0, !suppressResumeSeek {
                    newPlayer.seek(to: resume)
                }
                suppressResumeSeek = false
            }
        }

        do {
            // 签名流地址 7 天过期且与密钥绑定，列表页缓存的 streamUrl 可能已因密钥轮转/多活节点不一致而失效。
            // 播放前优先拉取新鲜签名；失败则回退到传入的 streamUrl 或本地拼接（预览兜底）。
            var freshStreamUrl: String? = streamUrl
            do {
                if let s = try await service.freshStreamPath(id: videoId), !s.isEmpty {
                    freshStreamUrl = s
                    MPVLog.log("fresh streamUrl fetched for \(videoId)")
                }
            } catch {
                MPVLog.log("fresh streamUrl fetch failed: \(error.localizedDescription)")
            }
            let playbackURL: String
            if let freshStreamUrl, let resolved = ServerConnection.shared.imageURL(for: freshStreamUrl)?.absoluteString {
                playbackURL = resolved
            } else if let streamUrl, let resolved = ServerConnection.shared.imageURL(for: streamUrl)?.absoluteString {
                playbackURL = resolved
            } else {
                playbackURL = service.streamURL(id: videoId).absoluteString
            }
            // freshStreamPath 也是 await：创建播放器前再校验一次（同上，防孤儿实例）
            if Task.isCancelled || saved {
                return
            }
            try newPlayer.create(
                url: playbackURL,
                httpHeaders: headers
            )
            player = newPlayer
            newPlayer.play()
            setupRemoteCommands()
            updateNowPlayingInfo()
            startCheckpointTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Metal 渲染视图初始化失败回调（T1-2）：复用播放页错误提示 UI 展示，不崩溃
    private func handleRenderFailure(_ message: String) {
        guard errorMessage == nil else { return }
        errorMessage = message
        MPVLog.log("render failure surfaced: \(message)")
    }

    /// 播放中每 15 秒周期上报一次，避免异常退出时进度丢失
    private func startCheckpointTimer() {
        checkpointTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [self] _ in
            Task { @MainActor in
                self.checkpointSave()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer
    }

    private func checkpointSave() {
        guard let player else { return }
        let position = player.position
        let duration = player.duration
        guard position.isFinite, position > 0 else { return }
        let id = videoId
        Task {
            await service.updatePosition(
                id: id,
                position: position,
                duration: duration.isFinite ? duration : 0
            )
        }
    }

    /// 退出播放器时上报最终进度（服务端自动判定是否看完）
    private func saveProgress() {
        guard !saved else { return }
        saved = true
        controlsHideTask?.cancel()
        hudDismissTask?.cancel()
        stopVolumePolling()
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        checkpointSave()
        player?.shutdown()
        // 断开回调，打断 player → 闭包 → 视图 @State 的引用环（否则实例永不释放），
        // 并阻止已入队的事件回调再触碰已销毁视图的状态
        player?.clearCallbacks()
        player = nil
        clearNowPlayingInfo()
        // 恢复音乐播放器的音频会话配置
        restoreMusicAudioSession()
    }

    /// 播放到结尾：只上报最终进度并展示"播放完毕"浮层，不销毁播放器
    /// （原实现复用 saveProgress()，把播放页变成无法恢复的"准备中…"）
    private func handlePlaybackFinished() {
        guard !isFinished else { return }
        isFinished = true
        isPlaying = false
        checkpointSave()
        updateNowPlayingInfo()
    }

    /// 从头重播：重新加载当前文件（续播 seek 由 suppressResumeSeek 跳过一次）
    private func replayFromStart() {
        guard let player else { return }
        isFinished = false
        suppressResumeSeek = true
        player.replay()
        player.play()
        isPlaying = true
        scheduleAutoHide()
        updateNowPlayingInfo()
    }

    private func restoreMusicAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    // MARK: - 锁屏/控制中心支持

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak player] _ in
            Task { @MainActor in
                player?.play()
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in
                player?.pause()
            }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in
                _ = player?.togglePause()
            }
            return .success
        }
        commands.changePlaybackRateCommand.addTarget { [weak player] event in
            guard let player, let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { @MainActor in
                player.setSpeed(Double(rateEvent.playbackRate))
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "视频播放" : title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0,
        ]
        if currentDuration.isFinite, currentDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = currentDuration
        }
        if let artwork = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // 不移除远程命令目标，避免清除音乐播放器注册的命令
        // 系统会在不同应用/场景间自动管理命令中心
    }
}

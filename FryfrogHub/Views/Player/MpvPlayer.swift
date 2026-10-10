import Foundation
import os

/// 文件级日志（Logger 为 Sendable，供 MainActor 方法与 nonisolated 事件线程共用）
private let mpvLogger = Logger(subsystem: "com.fryfrog.hub", category: "mpv")

/// libmpv 客户端封装（基于 mpv/client.h + mpv/render.h）。
/// 负责创建/初始化实例、选项、命令、属性监听与事件循环；
/// 渲染采用软件输出（MPV_RENDER_API_TYPE_SW），由 MpvRenderView 上传到 Metal 显示。
@MainActor
final class MpvPlayer {
    /// 状态回调
    var onPosition: ((Double) -> Void)?
    var onDuration: ((Double) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    var onEndReached: (() -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    /// 已缓冲时长变化（秒，demuxer-cache-duration）
    var onCacheDuration: ((Double) -> Void)?
    /// 新帧可渲染回调（由渲染视图驱动重绘）
    var onFrame: (() -> Void)?
    /// 视频尺寸变化（像素）
    var onVideoSize: ((Int, Int) -> Void)?

    private var handle: OpaquePointer?
    /// 当前加载的播放地址（供播完后 replay 重新 loadfile）
    private var currentURL: String?
    // T5-1：renderContext 需支持后台线程 renderFrame 无跳主线程调用，改为手动锁保护
    nonisolated(unsafe) private var renderContext: OpaquePointer?
    nonisolated(unsafe) private let renderContextLock = NSLock()
    /// 跨线程停止标志：主线程 shutdown 置 false，事件线程轮询（锁保证可见性）
    private let running = RunningFlag()
    // T1-3 复核结论：此信号量仅用于同步"专用事件线程退出"，wait 发生在主线程同步方法
    // shutdown() 内且有 1s 超时上限，不阻塞 Swift 协作线程池，用法合规，保留
    private let eventLoopStopped = DispatchSemaphore(value: 0)
    private(set) var videoWidth = 0
    private(set) var videoHeight = 0
    /// 本 app 经 sub-add 加载过的外挂字幕轨 id（track-list 随文件加载清空，见 FILE_LOADED）
    private var addedExternalSubIDs: Set<Int> = []

    private let propertyUserData: UInt64 = 1

    /// 释放 mpv 实例（由持有者在主线程显式调用）
    func shutdown() {
        let wasRunning = running.value
        running.value = false
        // mpv_destroy must not race with mpv_wait_event on the event thread.
        if wasRunning {
            _ = eventLoopStopped.wait(timeout: .now() + 1)
        }
        renderContextLock.lock()
        if let ctx = renderContext {
            mpv_render_context_free(ctx)
            self.renderContext = nil
        }
        renderContextLock.unlock()
        if let handle {
            mpv_destroy(handle)
            self.handle = nil
        }
    }

    /// 断开所有状态回调。持有者销毁时调用，打断
    /// "player → 闭包 → 视图 @State → player" 引用环，并阻止迟到的事件回调触碰已销毁视图。
    func clearCallbacks() {
        onPosition = nil
        onDuration = nil
        onPauseChanged = nil
        onEndReached = nil
        onReady = nil
        onError = nil
        onCacheDuration = nil
        onFrame = nil
        onVideoSize = nil
    }

    /// 从头重新加载当前文件（播放结束后重播；http-header-fields 仍是 create 时的选项，无需重传）
    func replay() {
        guard let handle, let currentURL else { return }
        command(["loadfile", currentURL])
    }

    /// 创建并初始化播放器实例
    /// - Parameters:
    ///   - url: 播放地址
    ///   - httpHeaders: 附加请求头（如 ["Authorization": "Bearer x"]）
    func create(url: String, httpHeaders: [String: String]) throws {
        MPVLog.log("create url=\(url)")
        guard let ctx = mpv_create() else {
            throw MpvError("创建播放器失败")
        }
        handle = ctx
        currentURL = url

        mpv_set_option_string(ctx, "idle", "yes")
        mpv_set_option_string(ctx, "keep-open", "no")
        mpv_set_option_string(ctx, "vo", "libmpv")
        // 解码方式：软解/硬解/自动（自动优先硬解、失败回退软解；SW 渲染下用 -copy 变体）
        mpv_set_option_string(ctx, "hwdec", PlayerSettings.shared.decodeMode.hwdecValue)
        // 网络缓存：显式开启并加大（默认值偏小，缓冲/拖动体验更好）
        mpv_set_option_string(ctx, "cache", "yes")
        mpv_set_option_string(ctx, "demuxer-max-bytes", "300MB")
        mpv_set_option_string(ctx, "demuxer-readahead-secs", "30")
        // iOS 构建只编译了 audiounit 音频输出（coreaudio 未启用）
        mpv_set_option_string(ctx, "ao", "audiounit")
        mpv_set_option_string(ctx, "audio-display", "no")
        mpv_set_option_string(ctx, "aid", "auto")
        mpv_set_option_string(ctx, "volume", "100")
        mpv_set_option_string(ctx, "mute", "no")
        mpv_set_option_string(ctx, "video-sync", "audio")
        if !httpHeaders.isEmpty {
            let fields = httpHeaders.map { "\($0.key): \($0.value)" }.joined(separator: ",\r\n")
            mpv_set_option_string(ctx, "http-header-fields", fields)
        }
        // 外挂字幕经菜单 sub-add 加载（列表来自后端同目录扫描）；
        // 关闭同名 sidecar 自动探测——对 /api/... 流地址只会打一串 404 噪音，且本后端流地址旁不存在可探测文件
        mpv_set_option_string(ctx, "sub-auto", "no")

        let initResult = mpv_initialize(ctx)
        MPVLog.log("initialize result=\(initResult)")
        if initResult < 0 {
            mpv_destroy(ctx)
            handle = nil
            throw MpvError("初始化播放器失败")
        }

        // 订阅 mpv 日志，便于排查（error 显示在播放器上，warn 进控制台）
        mpv_request_log_messages(ctx, "warn")

        mpv_observe_property(ctx, propertyUserData, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, propertyUserData, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, propertyUserData, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, propertyUserData, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, propertyUserData, "width", MPV_FORMAT_INT64)
        mpv_observe_property(ctx, propertyUserData, "height", MPV_FORMAT_INT64)
        mpv_observe_property(ctx, propertyUserData, "demuxer-cache-duration", MPV_FORMAT_DOUBLE)

        createRenderContext()
        startEventLoop()

        command(["loadfile", url])
    }

    // MARK: - 渲染上下文（软件输出）

    private func createRenderContext() {
        guard let handle else { return }
        var ctx: OpaquePointer?
        // API 名必须用 withCString 传真正的 C 字符串。
        // 不能直接取 &String：mpv 会把 String 结构体内存当 char* 读（小字符串恰好内联了
        // 字符字节才侥幸可用，换长字符串/新系统会读出垃圾指针）
        let rc = MPV_RENDER_API_TYPE_SW.withCString { apiCString in
            var params: [mpv_render_param] = [
                mpv_render_param(
                    type: MPV_RENDER_PARAM_API_TYPE,
                    data: UnsafeMutableRawPointer(mutating: apiCString)
                ),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return params.withUnsafeMutableBufferPointer { paramsBuffer in
                mpv_render_context_create(&ctx, handle, paramsBuffer.baseAddress)
            }
        }
        MPVLog.log("render context create result=\(rc)")
        mpvLogger.info("render context create result=\(rc, privacy: .public)")
        guard rc >= 0, let ctx else {
            onError?("创建渲染上下文失败")
            return
        }
        renderContextLock.lock()
        renderContext = ctx
        renderContextLock.unlock()
        MPVLog.log("render context ready (SW)")

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(ctx, { ctx in
            guard let ctx else { return }
            let player = Unmanaged<MpvPlayer>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                player.onFrame?()
            }
        }, selfPtr)
        mpvLogger.info("render context ready (SW)")
    }

    /// 软件渲染一帧到指定 BGRA 缓冲区（须与 MpvRenderView 的缓冲生命周期匹配）
    /// T5-1：改为 nonisolated 以允许后台队列直接调用，不跳主线程；用锁保护 renderContext 生命周期
    nonisolated func renderFrame(to buffer: UnsafeMutableRawPointer, width: Int, height: Int, stride: Int, flipY: Bool) {
        renderContextLock.lock()
        guard let ctx = renderContext else {
            renderContextLock.unlock()
            return
        }
        // SW_SIZE 是 int[2]（宽、高）。必须用元组（元素内联在值中）；不能用数组——
        // &array 指向的是数组结构体（内部堆指针），mpv 会把指针字节当宽高读出垃圾值
        var size = (Int32(width), Int32(height))
        // SW_STRIDE 类型是 size_t*（64 位），必须用 Int 而不是 Int32
        var strideValue = stride
        var flip: Int32 = flipY ? 1 : 0
        // SW_FORMAT 只接受 rgb0/bgr0/0bgr/0rgb 等内部格式名，bgra0 不存在会导致渲染失败
        let result = withUnsafeMutablePointer(to: &size) { sizePointer in
            withUnsafeMutablePointer(to: &strideValue) { stridePointer in
                withUnsafeMutablePointer(to: &flip) { flipPointer in
                    "bgr0".withCString { formatPointer in
                        var params: [mpv_render_param] = [
                            mpv_render_param(
                                type: MPV_RENDER_PARAM_SW_SIZE,
                                data: UnsafeMutableRawPointer(sizePointer)
                            ),
                            mpv_render_param(
                                type: MPV_RENDER_PARAM_SW_FORMAT,
                                data: UnsafeMutableRawPointer(mutating: formatPointer)
                            ),
                            mpv_render_param(
                                type: MPV_RENDER_PARAM_SW_STRIDE,
                                data: UnsafeMutableRawPointer(stridePointer)
                            ),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer),
                            mpv_render_param(
                                type: MPV_RENDER_PARAM_FLIP_Y,
                                data: UnsafeMutableRawPointer(flipPointer)
                            ),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                        ]
                        return params.withUnsafeMutableBufferPointer { paramsBuffer in
                            mpv_render_context_render(ctx, paramsBuffer.baseAddress)
                        }
                    }
                }
            }
        }
        renderContextLock.unlock()
        if result < 0 {
            MPVLog.log("render FAILED result=\(result)")
            mpvLogger.error("render failed result=\(result, privacy: .public)")
        }
    }

    // MARK: - 控制

    func play() {
        guard let handle else { return }
        var value: Int32 = 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &value)
    }

    func pause() {
        guard let handle else { return }
        var value: Int32 = 1
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &value)
    }

    func togglePause() -> Bool {
        let isPaused = paused
        isPaused ? play() : pause()
        return !isPaused
    }

    var paused: Bool {
        guard let handle else { return true }
        var value: Int32 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &value)
        return value == 1
    }

    func seek(to seconds: Double) {
        guard let handle else { return }
        var value = seconds
        mpv_set_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &value)
    }

    var position: Double {
        guard let handle else { return 0 }
        var value: Double = 0
        mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &value)
        return value
    }

    var duration: Double {
        guard let handle else { return 0 }
        var value: Double = 0
        mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &value)
        return value
    }

    private func command(_ args: [String]) {
        guard let handle else { return }
        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cargs.append(nil)
        // mpv_command 期望 [UnsafePointer<CChar>?]，与可变指针数组内存布局一致
        cargs.withUnsafeBufferPointer { buf in
            let raw = UnsafeMutableRawPointer(mutating: buf.baseAddress!)
            let typed = raw.bindMemory(to: UnsafePointer<CChar>?.self, capacity: cargs.count)
            mpv_command(handle, typed)
        }
        cargs.forEach { free($0) }
    }

    // MARK: - 字幕

    /// 字幕选择
    enum SubtitleSelection {
        case off
        case builtin(sid: Int)
        case external(url: String)
    }

    /// 读取当前字幕轨列表（track-list，含容器内置轨与 sub-add 加载的外挂轨）
    func fetchSubtitleTracks() -> [SubtitleTrack] {
        guard let handle else { return [] }
        var count: Int64 = 0
        guard mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count) >= 0 else { return [] }
        var tracks: [SubtitleTrack] = []
        for i in 0..<count {
            guard stringProperty("track-list/\(i)/type") == "sub" else { continue }
            // sid 必须用轨道真实 id（track-list/N/id），列表索引 i 不可用（轨道含视频/音频）
            var trackId: Int64 = -1
            mpv_get_property(handle, "track-list/\(i)/id", MPV_FORMAT_INT64, &trackId)
            let lang = stringProperty("track-list/\(i)/lang")
            let title = stringProperty("track-list/\(i)/title")
            MPVLog.log("sub track id=\(trackId) lang=\(lang ?? "nil") title=\(title ?? "nil")")
            tracks.append(SubtitleTrack(
                id: Int(trackId),
                lang: lang,
                title: title
            ))
        }
        return tracks
    }

    /// 应用字幕选择（先移除本 app 加载过的外挂轨，避免 track-list 无限增长）
    func selectSubtitle(_ selection: SubtitleSelection) {
        guard let handle else { return }
        removeExternalSubtitles()
        switch selection {
        case .off:
            mpv_set_property_string(handle, "sid", "no")
        case .builtin(let sid):
            mpv_set_property_string(handle, "sid", String(sid))
        case .external(let url):
            let before = externalTrackIDs()
            command(["sub-add", url, "select"])
            // 记录本次 sub-add 新增的轨 id（仅这些可被 sub-remove），供下次切换时清理；
            // mpv 对不支持的格式 sub-add 会失败，此时无新增 id，静默无副作用
            addedExternalSubIDs.formUnion(externalTrackIDs().subtracting(before))
        }
    }

    /// 移除本 app 经 sub-add 加载过的外挂字幕轨。
    /// 只删自己加的：mpv 属性名是 external（track-list/N/external，0.36 无 is-external），
    /// 且 sub-auto 自动加载的 sidecar 轨也是 external——不能碰，否则"选中后先被删再设 sid"会选到已删除的 id
    private func removeExternalSubtitles() {
        guard let handle, !addedExternalSubIDs.isEmpty else { return }
        for id in addedExternalSubIDs {
            command(["sub-remove", String(id)])
        }
        addedExternalSubIDs.removeAll()
    }

    /// 当前 track-list 中所有外挂字幕轨 id（track-list/N/external == 1）
    private func externalTrackIDs() -> Set<Int> {
        guard let handle else { return [] }
        var count: Int64 = 0
        guard mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count) >= 0 else { return [] }
        var ids: Set<Int> = []
        for i in 0..<count {
            var isExternal: Int32 = 0
            mpv_get_property(handle, "track-list/\(i)/external", MPV_FORMAT_FLAG, &isExternal)
            if isExternal == 1 {
                if let id = int64Property("track-list/\(i)/id"), id > 0 {
                    ids.insert(Int(id))
                }
            }
        }
        return ids
    }

    /// 读字符串属性（MPV_FORMAT_STRING，用完释放）
    private func stringProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        var ptr: UnsafeMutablePointer<CChar>?
        guard mpv_get_property(handle, name, MPV_FORMAT_STRING, &ptr) >= 0, let ptr else { return nil }
        defer { mpv_free(ptr) }
        return String(cString: ptr)
    }

    /// 读 double 属性
    private func doubleProperty(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value: Double = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 else { return nil }
        return value
    }

    /// 读 int64 属性
    private func int64Property(_ name: String) -> Int64? {
        guard let handle else { return nil }
        var value: Int64 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }

    // MARK: - 播放速度

    /// 设置播放速度（倍速，如 1.5 表示 1.5 倍速；mpv position/duration 不受倍速缩放）
    func setSpeed(_ rate: Double) {
        guard let handle, rate.isFinite, rate > 0 else { return }
        mpv_set_property_string(handle, "speed", String(rate))
    }

    /// 当前播放速度（默认 1.0）
    var currentSpeed: Double {
        guard let handle else { return 1.0 }
        var value: Double = 0
        guard mpv_get_property(handle, "speed", MPV_FORMAT_DOUBLE, &value) >= 0,
              value.isFinite, value > 0 else { return 1.0 }
        return value
    }

    // MARK: - 播放信息

    /// 读取当前视频的播放信息（分辨率/编码/码率/帧率等），供信息面板展示
    func fetchPlaybackInfo() -> PlaybackInfo {
        // mpv 0.36 无 protocol 属性（仅 protocol-list），从 path（完整 URL）解析协议前缀
        let protocolName: String? = stringProperty("path").flatMap { path in
            guard let range = path.range(of: "://") else { return nil }
            return String(path[..<range.lowerBound])
        }
        return PlaybackInfo(
            width: videoWidth,
            height: videoHeight,
            pixelFormat: stringProperty("video-params/pixel_format"),
            videoCodec: stringProperty("video-codec"),
            fps: doubleProperty("container-fps"),
            // mpv video-bitrate/audio-bitrate 单位为 bps（文档明确），非 kbps
            videoBitrateBps: doubleProperty("video-bitrate"),
            audioCodec: stringProperty("audio-codec"),
            audioChannels: stringProperty("audio-params/channels"),
            audioSampleRate: int64Property("audio-params/samplerate"),
            audioBitrateBps: doubleProperty("audio-bitrate"),
            containerFormat: stringProperty("file-format"),
            protocolName: protocolName,
            hwdecCurrent: stringProperty("hwdec-current"),
            dynamicRange: detectDynamicRange(),
            cacheDuration: doubleProperty("demuxer-cache-duration"),
            subtitleTrackCount: fetchSubtitleTracks().count
        )
    }

    /// 检测动态范围：HDR10/Dolby Vision/SDR 等
    private func detectDynamicRange() -> String? {
        guard let transfer = stringProperty("video-params/transfer") else { return nil }
        switch transfer {
        case "smpte2084": return "HDR10"
        case "arib-std-b67": return "HLG"
        default: return "SDR"
        }
    }

    // MARK: - 事件循环

    private func startEventLoop() {
        guard let handle, !running.value else { return }
        running.value = true
        // OpaquePointer 非 Sendable，经 box 显式声明约束：指针仅在事件线程内解包使用，
        // 生命周期由 shutdown() 的退出同步保证
        let context = EventContext(eventHandle: handle, running: running)
        // 专用线程轮询 mpv_wait_event（最长阻塞 0.02s），不可用协作线程池；
        // 循环内不触碰 MainActor 隔离状态：标志经 RunningFlag、事件解析在 nonisolated
        // handleEvent 内完成后统一 DispatchQueue.main 派发
        Thread.detachNewThread { [weak self] in
            defer { self?.eventLoopStopped.signal() }
            while context.running.value {
                guard let event = mpv_wait_event(context.eventHandle, 0.02) else { continue }
                if event.pointee.event_id == MPV_EVENT_NONE { continue }
                self?.handleEvent(event)
            }
        }
    }

    /// 运行于 mpv 事件线程：须在下一次 mpv_wait_event 前完成事件指针读取（mpv API 约束）；
    /// 函数体仅做 C 内存读取与日志，所有 UI/状态变更均经主线程派发，故声明为 nonisolated
    private nonisolated func handleEvent(_ event: UnsafePointer<mpv_event>!) {
        let id = event.pointee.event_id
        switch id {
        case MPV_EVENT_PROPERTY_CHANGE:
            let data = event.pointee.data.assumingMemoryBound(to: mpv_event_property.self)
            let name = String(cString: data.pointee.name)
            // mpv 事件数据仅保留至下一次 mpv_wait_event，必须在事件线程内完成解引用，
            // 跨线程只传值类型，消除主线程延迟读悬垂指针的竞态
            let decoded = PropertyValue.decode(format: data.pointee.format, from: data.pointee.data)
            DispatchQueue.main.async { [weak self] in
                self?.handlePropertyChange(name: name, value: decoded)
            }
        case MPV_EVENT_FILE_LOADED:
            // 仅文件加载完成（track-list 就绪）时触发，START_FILE 时轨道信息尚不可用
            DispatchQueue.main.async { [weak self] in
                // 新文件加载会重建 track-list，旧的外挂轨 id 已失效，先清掉避免误删新文件的轨
                self?.addedExternalSubIDs.removeAll()
                self?.onReady?()
            }
        case MPV_EVENT_END_FILE:
            let data = event.pointee.data.assumingMemoryBound(to: mpv_event_end_file.self)
            if data.pointee.reason == MPV_END_FILE_REASON_EOF {
                DispatchQueue.main.async { [weak self] in
                    self?.onEndReached?()
                }
            }
        case MPV_EVENT_LOG_MESSAGE:
            let data = event.pointee.data.assumingMemoryBound(to: mpv_event_log_message.self)
            let level = String(cString: data.pointee.level)
            if let textPtr = data.pointee.text {
                let text = String(cString: textPtr)
                MPVLog.log("msg[\(level)] \(text)")
                mpvLogger.info("mpv[\(level, privacy: .public)] \(text, privacy: .public)")
                if level == "error" {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 字幕相关错误（解码器缺失、外挂格式不支持致 sub-add/sub-remove 失败、
                    // sidecar 打不开等）只影响该字幕轨，不影响播放，不弹播放器错误浮层（记日志即可）
                    let isSubtitleIssue = trimmed.localizedCaseInsensitiveContains("subtitle")
                        || trimmed.contains("sub-add")
                        || trimmed.contains("sub-remove")
                        || trimmed.contains("Can not open external file")
                    if !isSubtitleIssue {
                        DispatchQueue.main.async { [weak self] in
                            self?.onError?(trimmed)
                        }
                    }
                }
            }
        default:
            break
        }
    }

    private func handlePropertyChange(name: String, value: PropertyValue?) {
        guard let value else { return }
        switch name {
        case "time-pos":
            if case .double(let v) = value { onPosition?(v) }
        case "duration":
            if case .double(let v) = value { onDuration?(v) }
        case "pause":
            if case .flag(let paused) = value { onPauseChanged?(paused) }
        case "eof-reached":
            if case .flag(true) = value { onEndReached?() }
        case "demuxer-cache-duration":
            if case .double(let v) = value { onCacheDuration?(v) }
        case "width":
            if case .int64(let v) = value { videoWidth = Int(v); notifySize() }
        case "height":
            if case .int64(let v) = value { videoHeight = Int(v); notifySize() }
        default:
            break
        }
    }

    private func notifySize() {
        if videoWidth > 0, videoHeight > 0 {
            MPVLog.log("video size \(videoWidth)x\(videoHeight)")
            onVideoSize?(videoWidth, videoHeight)
        }
    }
}

/// mpv 错误
struct MpvError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 属性变更值载荷：在 mpv 事件线程内解码为 Sendable 值类型后跨线程传递，
/// 避免主队列延迟解引用已失效的事件内存
private enum PropertyValue: Sendable {
    case double(Double)
    case flag(Bool)
    case int64(Int64)

    /// 按观察属性时声明的格式解引用原始数据；未支持的格式或空指针返回 nil（与旧行为一致地跳过）
    static func decode(format: mpv_format, from raw: UnsafeMutableRawPointer?) -> PropertyValue? {
        guard let raw else { return nil }
        switch format {
        case MPV_FORMAT_DOUBLE: return .double(raw.load(as: Double.self))
        case MPV_FORMAT_FLAG: return .flag(raw.load(as: Int32.self) == 1)
        case MPV_FORMAT_INT64: return .int64(raw.load(as: Int64.self))
        default: return nil
        }
    }
}

/// 锁保护的运行标志：主线程（shutdown 置 false）与 mpv 事件线程（轮询读取）跨线程共享
private final class RunningFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isRunning = false

    var value: Bool {
        get { lock.withLock { isRunning } }
        set { lock.withLock { isRunning = newValue } }
    }
}

/// 事件线程捕获上下文：OpaquePointer 非 Sendable，经 box 显式声明约束
/// （指针仅在事件线程解包使用；生命周期由 shutdown() 的退出同步保证）
private struct EventContext: @unchecked Sendable {
    let eventHandle: OpaquePointer
    let running: RunningFlag
}

/// 字幕轨描述（id 为 mpv track-list 的轨道 id，含内置轨与 sub-add 外挂轨）
struct SubtitleTrack {
    let id: Int
    let lang: String?
    let title: String?
}

/// 播放信息（信息面板展示用）
struct PlaybackInfo {
    let width: Int
    let height: Int
    let pixelFormat: String?
    let videoCodec: String?
    let fps: Double?
    /// 视频码率（bps）
    let videoBitrateBps: Double?
    let audioCodec: String?
    let audioChannels: String?
    let audioSampleRate: Int64?
    /// 音频码率（bps）
    let audioBitrateBps: Double?
    let containerFormat: String?
    let protocolName: String?
    /// 实际生效的解码模式（mpv hwdec-current："no"=软解 / "videotoolbox-copy" 等=硬解）
    let hwdecCurrent: String?
    /// 动态范围（"SDR" / "HDR" / "HDR10" / "HDR10+" / "Dolby Vision" 等）
    let dynamicRange: String?
    /// 已缓冲时长（秒，demuxer-cache-duration）
    let cacheDuration: Double?
    let subtitleTrackCount: Int
}

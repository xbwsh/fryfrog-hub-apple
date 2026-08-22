import Foundation
import os

/// libmpv 客户端封装（基于 mpv/client.h + mpv/render.h）。
/// 负责创建/初始化实例、选项、命令、属性监听与事件循环；
/// 渲染采用软件输出（MPV_RENDER_API_TYPE_SW），由 MpvRenderView 上传到 Metal 显示。
@MainActor
final class MpvPlayer {
    private static let logger = Logger(subsystem: "com.fryfrog.hub", category: "mpv")
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
    private var renderContext: OpaquePointer?
    private var running = false
    private let eventLoopStopped = DispatchSemaphore(value: 0)
    private(set) var videoWidth = 0
    private(set) var videoHeight = 0

    private let propertyUserData: UInt64 = 1

    /// 释放 mpv 实例（由持有者在主线程显式调用）
    func shutdown() {
        let wasRunning = running
        running = false
        // mpv_destroy must not race with mpv_wait_event on the event thread.
        if wasRunning {
            _ = eventLoopStopped.wait(timeout: .now() + 1)
        }
        if let renderContext {
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }
        if let handle {
            mpv_destroy(handle)
            self.handle = nil
        }
    }

    /// 创建并初始化播放器实例
    /// - Parameters:
    ///   - url: 播放地址
    ///   - httpHeaders: 附加请求头（如 ["Authorization": "Bearer x"]）
    ///   - startPosition: 起始位置（秒）
    func create(url: String, httpHeaders: [String: String], startPosition: Double) throws {
        MPVLog.log("create url=\(url) start=\(startPosition)")
        guard let ctx = mpv_create() else {
            throw MpvError("创建播放器失败")
        }
        handle = ctx

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
        // 外挂字幕自动加载（同目录同名）
        mpv_set_option_string(ctx, "sub-auto", "fuzzy")

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

        if startPosition > 0 {
            var pos = startPosition
            mpv_set_property(ctx, "start", MPV_FORMAT_DOUBLE, &pos)
        }
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
        Self.logger.info("render context create result=\(rc, privacy: .public)")
        guard rc >= 0, let ctx else {
            onError?("创建渲染上下文失败")
            return
        }
        renderContext = ctx
        MPVLog.log("render context ready (SW)")

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(ctx, { ctx in
            guard let ctx else { return }
            let player = Unmanaged<MpvPlayer>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                player.onFrame?()
            }
        }, selfPtr)
        Self.logger.info("render context ready (SW)")
    }

    /// 软件渲染一帧到指定 BGRA 缓冲区（须与 MpvRenderView 的缓冲生命周期匹配）
    func renderFrame(to buffer: UnsafeMutableRawPointer, width: Int, height: Int, stride: Int, flipY: Bool) {
        guard let renderContext else { return }
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
                            mpv_render_context_render(renderContext, paramsBuffer.baseAddress)
                        }
                    }
                }
            }
        }
        if result < 0 {
            MPVLog.log("render FAILED result=\(result)")
            Self.logger.error("render failed result=\(result, privacy: .public)")
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

    /// 读取当前字幕轨列表（track-list，仅内置轨；外挂轨经 sub-add 后也会出现在列表末尾）
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

    /// 应用字幕选择（先移除旧外挂轨，避免与内置轨叠加显示）
    func selectSubtitle(_ selection: SubtitleSelection) {
        guard let handle else { return }
        removeExternalSubtitles()
        switch selection {
        case .off:
            mpv_set_property_string(handle, "sid", "no")
        case .builtin(let sid):
            mpv_set_property_string(handle, "sid", String(sid))
        case .external(let url):
            command(["sub-add", url, "select"])
        }
    }

    /// 移除所有外挂字幕轨（sub-remove 只接受数字轨道 id，不支持 "all"）
    private func removeExternalSubtitles() {
        guard let handle else { return }
        var count: Int64 = 0
        guard mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count) >= 0 else { return }
        var externalIds: [Int] = []
        for i in 0..<count {
            var isExternal: Int32 = 0
            mpv_get_property(handle, "track-list/\(i)/is-external", MPV_FORMAT_FLAG, &isExternal)
            if isExternal == 1 {
                var trackId: Int64 = -1
                mpv_get_property(handle, "track-list/\(i)/id", MPV_FORMAT_INT64, &trackId)
                if trackId > 0 { externalIds.append(Int(trackId)) }
            }
        }
        for id in externalIds {
            command(["sub-remove", String(id)])
        }
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
        guard let handle, !running else { return }
        running = true
        let eventHandle = handle
        Thread.detachNewThread { [weak self, eventHandle] in
            guard let self else { return }
            defer { self.eventLoopStopped.signal() }
            while self.running {
                guard let event = mpv_wait_event(eventHandle, 0.02) else { continue }
                if event.pointee.event_id == MPV_EVENT_NONE { continue }
                self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
        let id = event.pointee.event_id
        switch id {
        case MPV_EVENT_PROPERTY_CHANGE:
            let data = event.pointee.data.assumingMemoryBound(to: mpv_event_property.self)
            let name = String(cString: data.pointee.name)
            let format = data.pointee.format
            let value = data.pointee.data
            DispatchQueue.main.async { [weak self] in
                self?.handlePropertyChange(name: name, format: format, value: value)
            }
        case MPV_EVENT_FILE_LOADED:
            // 仅文件加载完成（track-list 就绪）时触发，START_FILE 时轨道信息尚不可用
            DispatchQueue.main.async { [weak self] in
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
                Self.logger.info("mpv[\(level, privacy: .public)] \(text, privacy: .public)")
                if level == "error" {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 字幕解码器缺失（如 PGS 图形字幕未编译进 ffmpeg）只影响该字幕轨，
                    // 不影响播放，不弹全屏错误（记日志即可）
                    if !trimmed.contains("subtitle decoder") {
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

    private func handlePropertyChange(name: String, format: mpv_format, value: UnsafeRawPointer?) {
        guard let value else { return }
        switch name {
        case "time-pos":
            if format == MPV_FORMAT_DOUBLE { onPosition?(value.load(as: Double.self)) }
        case "duration":
            if format == MPV_FORMAT_DOUBLE { onDuration?(value.load(as: Double.self)) }
        case "pause":
            if format == MPV_FORMAT_FLAG { onPauseChanged?(value.load(as: Int32.self) == 1) }
        case "eof-reached":
            if format == MPV_FORMAT_FLAG, value.load(as: Int32.self) == 1 { onEndReached?() }
        case "demuxer-cache-duration":
            if format == MPV_FORMAT_DOUBLE { onCacheDuration?(value.load(as: Double.self)) }
        case "width":
            if format == MPV_FORMAT_INT64 { videoWidth = Int(value.load(as: Int64.self)); notifySize() }
        case "height":
            if format == MPV_FORMAT_INT64 { videoHeight = Int(value.load(as: Int64.self)); notifySize() }
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

/// 字幕轨描述（仅内置轨，id 为 mpv track-list 索引）
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

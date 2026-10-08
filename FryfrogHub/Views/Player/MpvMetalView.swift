import SwiftUI
import Metal
import MetalKit
import QuartzCore
import os

/// CADisplayLink 的弱引用代理 target：displayLink 强持有本对象而非视图，
/// 切断 视图 → displayLink → 视图 引用环（否则视图永不 deinit，displayLink 永久 tick）
private final class DisplayLinkProxy: NSObject {
    weak var view: MpvMetalView?

    init(view: MpvMetalView) {
        self.view = view
    }

    @objc func handleTick() {
        view?.tick()
    }
}

/// 用 Metal 显示 mpv 软件渲染输出的视频画面。
/// 渲染循环：CADisplayLink 驱动 → mpv 软件渲染到 CPU 缓冲区 → 上传 Metal 纹理 → 全屏三角形绘制。
final class MpvMetalView: UIView {
    let player: MpvPlayer

    private let metalLayer = CAMetalLayer()
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let pipeline: MTLRenderPipelineState
    private var displayLink: CADisplayLink?
    /// displayLink 强持有的代理 target（弱引用回视图），见 startRendering 注释
    private var displayLinkProxy: DisplayLinkProxy?

    /// 渲染目标缓冲区（BGRA）与复用纹理
    private var frameBuffer: UnsafeMutableRawPointer?
    private var frameTexture: MTLTexture?
    private var frameStride = 0
    private var frameWidth = 0
    private var frameHeight = 0

    /// T5-1 后台渲染：串行队列 + 锁 + 渲染中去重，主线程只做 Metal 提交
    private let renderQueue = DispatchQueue(label: "com.fryfrog.hub.mpv-render", qos: .userInitiated)
    private let bufferLock = NSLock()
    private var isRendering = false

    /// 是否需要重绘（mpv 更新回调置位）
    private var needsRedraw = false
    private var didLogSkip = false
    /// 视频尺寸变化回调（SwiftUI 端据此按原始比例布局）
    var onSizeChange: ((CGSize) -> Void)?
    #if DEBUG
    private var frameCount = 0
    #endif
    private static let logger = Logger(subsystem: "com.fryfrog.hub", category: "mpv-render")

    /// T1-2：Metal 初始化改为可失败——设备缺失/命令队列失败/着色器或管线编译失败时返回 nil
    /// 并记录日志，由上层（MpvMetalViewContainer）回退占位视图并提示错误，不再 fatalError/try! 崩溃
    init?(player: MpvPlayer, frame: CGRect) {
        self.player = player
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logFailure("Metal 设备不可用（MTLCreateSystemDefaultDevice 返回 nil）")
            return nil
        }
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            Self.logFailure("Metal 命令队列创建失败")
            return nil
        }
        self.commandQueue = commandQueue
        // 运行时编译着色器（避免依赖 Metal 工具链编译 .metal 文件）
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            Self.logFailure("着色器库编译失败: \(error)")
            return nil
        }
        self.library = library
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mpvVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mpvFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Self.logFailure("渲染管线状态创建失败: \(error)")
            return nil
        }
        self.pipeline = pipelineState
        super.init(frame: frame)

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        layer.addSublayer(metalLayer)

        player.onFrame = { [weak self] in
            self?.needsRedraw = true
        }
        player.onVideoSize = { [weak self] width, height in
            MPVLog.log("view video size \(width)x\(height)")
            self?.prepareBuffer(width: width, height: height)
        }
        // onVideoSize 事件可能在视图挂载前已触发，这里按当前已知尺寸补建缓冲区
        if player.videoWidth > 0, player.videoHeight > 0 {
            prepareBuffer(width: player.videoWidth, height: player.videoHeight)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 初始化失败的统一记录（mpv.log + 系统日志，供"UI 提示可观测"验收排查）
    private static func logFailure(_ reason: String) {
        MPVLog.log("MpvMetalView init failed: \(reason)")
        logger.error("MpvMetalView init failed: \(reason, privacy: .public)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func startRendering() {
        guard displayLink == nil else { return }
        // CADisplayLink 强持有 target。若 target 直接是 self，会形成
        // 视图 → displayLink → 视图 的引用环：stopRendering/deinit 永不执行，
        // 每次播放泄漏帧缓冲 + Metal 资源，displayLink 还会以屏幕刷新率永久唤醒主线程。
        // 经弱引用代理承接，环被切断，deinit 正常执行并 invalidate。
        let proxy = DisplayLinkProxy(view: self)
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
    }

    /// T5-1：移除 30fps 限帧（对齐飞牛：后台渲染已为主线程让路，无需压帧）
    /// 原 T4-2 在控件显期 30fps 会导致 60fps 源抽帧抖动（F-003）且开场 4s 恒 30fps（F-002）；
    /// 现切后台渲染后全程满帧，控件动画由后台保障。保留方法以兼容容器透传。
    func setControlsVisible(_ visible: Bool) {
        // 全程满帧，避免 60fps 抽帧；如需动画窗口内微调，可在此按 visible 做 0.3s 临时限帧
        _ = visible
        displayLink?.preferredFramesPerSecond = 0
        if #available(iOS 15.0, *) {
            // ProMotion 上 0 已等价于 maximum 帧率，无需 preferredFrameRateRange 额外设置
        }
    }

    deinit {
        stopRendering()
        // 等待后台渲染完成再释放，避免后台仍持有旧缓冲
        renderQueue.sync {}
        bufferLock.lock()
        if let buf = frameBuffer {
            free(buf)
            frameBuffer = nil
        }
        bufferLock.unlock()
    }

    /// 内嵌 MSL 源码：全屏三角形 + BGRA 纹理采样
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct MpvVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex MpvVertexOut mpvVertex(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        float2 uvs[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };
        MpvVertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment float4 mpvFragment(MpvVertexOut in [[stage_in]],
                                texture2d<float> texture [[texture(0)]]) {
        constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
        return texture.sample(s, in.uv);
    }
    """

    // MARK: - 渲染

    fileprivate func tick() {
        // T5-1：主线程只做状态快照与 Metal 提交，软解放到 renderQueue
        bufferLock.lock()
        let hasBuffer = frameBuffer != nil
        let w = frameWidth
        let h = frameHeight
        bufferLock.unlock()
        guard hasBuffer, w > 0, h > 0 else {
            if !didLogSkip {
                MPVLog.log("tick skip needsRedraw=\(needsRedraw) size=\(w)x\(h) buf=\(hasBuffer)")
                didLogSkip = true
            }
            return
        }
        guard needsRedraw, !isRendering else {
            return
        }
        needsRedraw = false
        isRendering = true

        #if DEBUG
        if frameCount % 60 == 0 {
            MPVLog.log("rendered frame \(frameCount) size \(w)x\(h) -> background")
        }
        frameCount += 1
        #endif

        // 快照当前缓冲（主线程串行，快照后若 prepareBuffer 重建，旧缓冲通过 renderQueue 延迟释放）
        bufferLock.lock()
        guard let buffer = frameBuffer, let texture = frameTexture else {
            bufferLock.unlock()
            isRendering = false
            return
        }
        let stride = frameStride
        let width = frameWidth
        let height = frameHeight
        bufferLock.unlock()

        // 1. 后台软解（不跳主线程，见 MpvPlayer.renderFrame nonisolated）
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.player.renderFrame(to: buffer, width: width, height: height, stride: stride, flipY: true)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // 若后台期间尺寸已变更，丢弃本帧并触发重绘
                self.bufferLock.lock()
                let currentW = self.frameWidth
                let currentH = self.frameHeight
                self.bufferLock.unlock()
                if currentW != width || currentH != height {
                    self.isRendering = false
                    self.needsRedraw = true
                    return
                }
                guard let drawable = self.metalLayer.nextDrawable(),
                      let commandBuffer = self.commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderPass(drawable)) else {
                    self.isRendering = false
                    return
                }
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: buffer, bytesPerRow: stride)
                encoder.setRenderPipelineState(self.pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                self.isRendering = false
            }
        }
    }

    private func renderPass(_ drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return descriptor
    }

    private func prepareBuffer(width: Int, height: Int) {
        // T5-1：加锁并延迟释放旧缓冲，避免后台 render 使用中被 free
        bufferLock.lock()
        guard width != frameWidth || height != frameHeight else {
            bufferLock.unlock()
            return
        }
        let oldBuffer = frameBuffer
        frameWidth = width
        frameHeight = height
        frameStride = width * 4
        frameBuffer = malloc(frameStride * height)

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        frameTexture = device.makeTexture(descriptor: textureDescriptor)
        needsRedraw = true
        bufferLock.unlock()
        if let old = oldBuffer {
            renderQueue.async {
                free(old)
            }
        }
        onSizeChange?(CGSize(width: width, height: height))
    }
}

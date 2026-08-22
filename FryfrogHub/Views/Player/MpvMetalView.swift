import SwiftUI
import Metal
import MetalKit
import QuartzCore
import os

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

    /// 渲染目标缓冲区（BGRA）与复用纹理
    private var frameBuffer: UnsafeMutableRawPointer?
    private var frameTexture: MTLTexture?
    private var frameStride = 0
    private var frameWidth = 0
    private var frameHeight = 0

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
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// T4-2：控件显示期间将渲染节拍降至 30fps，为控制栏淡入淡出等 UI 动画让出
    /// 主线程余量；隐藏后恢复设备默认帧率（0 = 跟随 maximumFramesPerSecond）。
    /// 需在 startRendering 之后调用方生效（displayLink 已创建）。
    func setControlsVisible(_ visible: Bool) {
        displayLink?.preferredFramesPerSecond = visible ? 30 : 0
    }

    deinit {
        stopRendering()
        if let frameBuffer {
            free(frameBuffer)
        }
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

    @objc private func tick() {
        guard needsRedraw, frameWidth > 0, frameHeight > 0, let frameBuffer else {
            // 未就绪时只记录一次，便于判断卡在哪一环
            if !didLogSkip {
                MPVLog.log("tick skip needsRedraw=\(needsRedraw) size=\(frameWidth)x\(frameHeight) buf=\(frameBuffer != nil)")
                didLogSkip = true
            }
            return
        }
        needsRedraw = false

        #if DEBUG
        if frameCount % 60 == 0 {
            MPVLog.log("rendered frame \(frameCount) size \(frameWidth)x\(frameHeight)")
        }
        frameCount += 1
        #endif

        // 1. mpv 软件渲染到 CPU 缓冲区
        player.renderFrame(
            to: frameBuffer,
            width: frameWidth,
            height: frameHeight,
            stride: frameStride,
            flipY: true
        )

        // 2. 上传 Metal 纹理
        guard let drawable = metalLayer.nextDrawable(),
              let frameTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        frameTexture.replace(
            region: MTLRegionMake2D(0, 0, frameWidth, frameHeight),
            mipmapLevel: 0,
            withBytes: frameBuffer,
            bytesPerRow: frameStride
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(drawable)) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frameTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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
        // 仅当尺寸变化时重新分配
        guard width != frameWidth || height != frameHeight else { return }
        if let frameBuffer {
            free(frameBuffer)
        }
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
        onSizeChange?(CGSize(width: width, height: height))
    }
}

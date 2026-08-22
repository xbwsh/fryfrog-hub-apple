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

    init(player: MpvPlayer, frame: CGRect) {
        self.player = player
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal 不可用")
        }
        self.device = device
        commandQueue = device.makeCommandQueue()!
        // 运行时编译着色器（避免依赖 Metal 工具链编译 .metal 文件）
        let library = try! device.makeLibrary(source: Self.shaderSource, options: nil)
        self.library = library
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mpvVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mpvFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
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

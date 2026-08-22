import SwiftUI
import ImageIO
import CryptoKit
import Observation

/// 带认证头的远程图片加载（封面/背景图等需要 Bearer Token）
/// 性能优化：后台降采样解码（ImageIO）+ 解码结果缓存 + 并发限制，避免主线程解码大图卡顿
struct ServerImageView: View {
    let path: String?
    var aspectRatio: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = .gray.opacity(0.2)

    var body: some View {
        if let url = ServerConnection.shared.imageURL(for: path) {
            AuthAsyncImage(url: url, contentMode: contentMode, placeholderColor: placeholderColor)
        } else {
            placeholderColor
        }
    }
}

/// 使用 URLSession 加载图片，自动附带 Bearer Token，带解码后缓存
struct AuthAsyncImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = .gray.opacity(0.2)

    private let loader = AuthImageLoader.shared

    @State private var uiImage: UIImage?
    @State private var didFail = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 同步读缓存：视图重建 / matchedGeometry 飞行副本首帧即显示封面，
                // 避免飞行期间以暗色占位块遮挡
                if let image = uiImage ?? loader.cached(url: url) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        // fit 模式（如标题艺术字）左对齐，从容器左侧开始显示
                        .frame(
                            width: geo.size.width,
                            height: geo.size.height,
                            alignment: contentMode == .fill ? .center : .leading
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    placeholderColor
                }
            }
        }
        .clipped()
        // 观察缓存世代号：手动刷新/purge 后世代 +1，触发已渲染的图片重新加载
        .task(id: taskID) {
            // url 切换时立即同步新缓存，否则旧 uiImage 会残留导致封面不更新（底部播放栏切歌不刷新）
            if let cached = loader.cached(url: url) {
                uiImage = cached
                didFail = false
            } else {
                // 先清空旧图，避免切歌瞬间仍显示上一首封面
                if uiImage != nil { uiImage = nil }
                await load()
            }
        }
        .onChange(of: url) { _, newURL in
            // url 变化但 taskID 竞态未触发时兜底刷新
            if let cached = loader.cached(url: newURL) {
                uiImage = cached
                didFail = false
            } else {
                uiImage = nil
            }
        }
    }

    private var taskID: String {
        "\(url.absoluteString)#\(loader.cacheGeneration)"
    }

    private func load() async {
        // 移除 guard uiImage==nil 阻断，切歌后旧图残留会导致新封面无法加载
        // 缓存优先：其它视图（如详情页）已加载成功时直接复用，不再重下
        if let cached = loader.cached(url: url) {
            uiImage = cached
            didFail = false
            return
        }
        // 上次失败后短暂等待再重试，避免在弱网/切换瞬间长期空白
        if didFail {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, uiImage == nil else { return }
            if let cached = loader.cached(url: url) {
                uiImage = cached
                didFail = false
                return
            }
        }
        do {
            uiImage = try await loader.loadScaled(url: url)
            didFail = false
        } catch {
            didFail = true
        }
    }
}

/// 带 Bearer Token 的图片加载器：降采样解码 + 内存/磁盘缓存 + 并发限制
@MainActor
@Observable
final class AuthImageLoader {
    static let shared = AuthImageLoader()

    /// 图片缓存本体放独立类并忽略观测，避免每张图缓存写入触发所有图片视图重渲染；
    /// 视图只观察 cacheGeneration，purge 时 +1 触发重载
    @ObservationIgnored private let store = ImageStore()
    /// 缓存世代号：手动刷新/purge 时 +1，已渲染的图片视图据此重启加载
    private(set) var cacheGeneration = 0

    /// 缓存上限（120 张 ≈ 峰值 400MB 以内，首页实际同时可见通常远低于此）
    private let maxCacheEntries = 120
    /// 降采样目标（最大边像素）：PosterCard 360pt 与轮播大图（~1206px @3x）均清晰
    private let maxPixelSize: CGFloat = 1200
    /// 并发上限（下载+解码同时最多 4 个，避免视频多时请求/解码风暴）
    private let concurrency = 4
    /// 下载并发闸门：actor/continuation 挂起实现，替代 DispatchSemaphore——
    /// 后者在 Task.detached 内 wait 会阻塞协作线程池线程，有优先级反转风险
    private let downloadGate = AsyncSemaphore(limit: 4)
    /// T3-1：客户端经协议注入，消除对 APIClient.shared 的硬编码依赖
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    func cached(url: URL) -> UIImage? {
        store.cache[url.path]
    }

    /// 加载：内存 → 磁盘（有效期内）→ 网络；网络失败时回退过期磁盘缓存
    func loadScaled(url: URL) async throws -> UIImage {
        if let cached = store.cache[url.path] { return cached }

        // 1) 磁盘缓存命中（未过期，磁盘 IO + 解码在后台）
        let diskResult: UIImage? = await Task.detached(priority: .utility) {
            guard let data = AuthImageDiskCache.read(urlPath: url.path) else { return nil }
            do {
                return try decodeScaled(data: data, maxPixelSize: 1200)
            } catch {
                AppLog.image.warning("磁盘缓存解码失败 \(url.path): \(AppLog.describe(error))")
                return nil
            }
        }.value
        if let decoded = diskResult {
            store(decoded, for: url)
            return decoded
        }

        // 2) 网络下载（限流：最多 concurrency 个同时在跑，等待许可为挂起而非阻塞），成功后写磁盘
        do {
            let data: Data = try await downloadGate.withPermit {
                var request = URLRequest(url: url)
                let token = await client.currentToken
                if let token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, _) = try await URLSession.shared.data(for: request)
                AuthImageDiskCache.write(data, urlPath: url.path)
                return data
            }

            let decoded: UIImage? = await Task.detached(priority: .utility) {
                do {
                    return try decodeScaled(data: data, maxPixelSize: 1200)
                } catch {
                    AppLog.image.warning("网络图片解码失败 \(url.path): \(AppLog.describe(error))")
                    return nil
                }
            }.value
            if let decoded {
                store(decoded, for: url)
                return decoded
            }
            throw ImageLoadError.invalidData
        } catch {
            // 3) 网络失败 → 回退过期磁盘缓存，尽力显示旧图
            AppLog.image.warning("封面下载失败 \(url.path): \(AppLog.describe(error))")
            let staleResult: UIImage? = await Task.detached(priority: .utility) {
                guard let data = AuthImageDiskCache.readStale(urlPath: url.path) else { return nil }
                do {
                    return try decodeScaled(data: data, maxPixelSize: 1200)
                } catch {
                    AppLog.image.warning("过期缓存解码失败 \(url.path): \(AppLog.describe(error))")
                    return nil
                }
            }.value
            if let stale = staleResult {
                store(stale, for: url)
                return stale
            }
            throw error
        }
    }

    /// 显式刷新元数据后清除某资源路径（如 `/api/v1/video/series/1/cover`）的内存与磁盘缓存，
    /// 让刚刷新的封面立即生效（内存按资源路径为键，局域网/公网/签名变化共用同一份）
    func purge(path: String?) {
        guard let path, !path.isEmpty else { return }
        if store.cache.removeValue(forKey: path) != nil {
            store.cacheOrder.removeAll { $0 == path }
        }
        cacheGeneration += 1
        Task.detached(priority: .utility) {
            AuthImageDiskCache.purge(urlPath: path)
        }
    }

    /// 清空全部图片缓存（内存 + 磁盘），手动刷新/排查封面更新时使用
    func purgeAll() {
        store.cache.removeAll()
        store.cacheOrder.removeAll()
        cacheGeneration += 1
        Task.detached(priority: .utility) {
            AuthImageDiskCache.purgeAll()
        }
    }

    private func store(_ image: UIImage, for url: URL) {
        let key = url.path
        store.cache[key] = image
        store.cacheOrder.append(key)
        if store.cacheOrder.count > maxCacheEntries {
            let overflow = store.cacheOrder.count - maxCacheEntries
            for i in 0..<overflow {
                store.cache.removeValue(forKey: store.cacheOrder[i])
            }
            store.cacheOrder.removeFirst(overflow)
        }
    }
}

/// 图片缓存容器（独立类，避免被 @Observable 逐条追踪导致性能损耗）
/// key 用资源路径（url.path），不含签名等查询参数，签名过期/轮换不影响命中
@MainActor
private final class ImageStore {
    var cache: [String: UIImage] = [:]
    var cacheOrder: [String] = []
}

/// 封面等图片的磁盘缓存（原始字节，按服务器资源路径为键）
/// 局域网/公网地址不同但资源路径相同，天然共用一份；有效期 7 天，超容量按最旧淘汰。
enum AuthImageDiskCache {
    /// 缓存有效期：封面只在显式刷新元数据时变化（届时会主动 purge），7 天内直接复用
    static let ttl: TimeInterval = 7 * 24 * 60 * 60
    /// 容量上限（约 200MB，远高于实际封面体积）
    static let maxBytes: Int64 = 200 * 1024 * 1024

    private static let directoryName = "FryfrogImages"

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func key(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(for path: String) -> URL {
        directory.appendingPathComponent(key(for: path))
    }

    /// 读取有效期内缓存；缺失或过期返回 nil
    static func read(urlPath: String) -> Data? {
        let file = fileURL(for: urlPath)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
        if Date().timeIntervalSince(mtime) > ttl { return nil }
        return data
    }

    /// 读取缓存（含过期），供网络失败时兜底
    static func readStale(urlPath: String) -> Data? {
        try? Data(contentsOf: fileURL(for: urlPath))
    }

    /// 写入缓存并淘汰超容量文件
    static func write(_ data: Data, urlPath: String) {
        let file = fileURL(for: urlPath)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file)
        } catch {
            AppLog.image.warning("封面磁盘缓存写入失败 \(urlPath): \(AppLog.describe(error))")
        }
        evictIfOverLimit()
    }

    /// 清除指定资源路径的缓存
    static func purge(urlPath: String) {
        try? FileManager.default.removeItem(at: fileURL(for: urlPath))
    }

    /// 清空全部图片缓存
    static func purgeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 超容量时按修改时间旧到新删除
    private static func evictIfOverLimit() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []
        ) else { return }

        let entries: [(url: URL, date: Date, size: Int64)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, Int64(size))
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > maxBytes else { break }
            do {
                try fm.removeItem(at: entry.url)
            } catch {
                AppLog.image.warning("封面缓存淘汰删除失败 \(entry.url.lastPathComponent): \(AppLog.describe(error))")
            }
            total -= entry.size
        }
    }
}

/// ImageIO 降采样解码：按最大边缩放，避免全尺寸解码占用大量内存/CPU
private func decodeScaled(data: Data, maxPixelSize: CGFloat) throws -> UIImage {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
        throw ImageLoadError.invalidData
    }
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
        throw ImageLoadError.invalidData
    }
    return UIImage(cgImage: cgImage)
}

private enum ImageLoadError: Error {
    case invalidData
}

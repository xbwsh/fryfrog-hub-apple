import Foundation
import Observation

/// 与 MusicService 等一致整体标注 @MainActor：groups/isLoading 仅主线程变更
/// （此前 fetchHomeContent 的 defer/catch 在通用执行器写状态，主线程同时遍历渲染 → 竞态）
@MainActor
@Observable
final class HomeService {
    static let shared = HomeService()

    private let client: any APIClientProtocol
    /// 预留：与其它 Service 统一注入契约（当前方法未直接使用）
    private let server: any ServerConnectionProtocol

    private(set) var groups: [LibrarySeriesGroup] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// 随机化后的轮播池缓存：只在数据刷新/隐私切换时重掷，避免 body 频繁重算导致乱跳
    private var cachedCarousel: [SeriesListDTO] = []

    /// T3-1：默认单例入口；测试可注入协议替身
    init(client: any APIClientProtocol = APIClient.shared, server: any ServerConnectionProtocol = ServerConnection.shared) {
        self.client = client
        self.server = server
    }

    /// 拉取按资源库分组的系列数据
    func fetchHomeContent() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: ApiResponse<[LibrarySeriesGroup]> = try await client.request(
                "/api/v1/video/series/grouped-by-library"
            )
            groups = response.data ?? []
            rollCarousel()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 轮播数据：加权随机后的内容池
    var carouselItems: [SeriesListDTO] { cachedCarousel }

    /// 重新掷轮播顺序（数据刷新后、隐私模式切换时调用）
    func rollCarousel() {
        cachedCarousel = randomizedCarousel()
    }

    /// 加权随机算法：
    /// - 有横屏背景图的条目优先（轮播是沉浸大图，无背景图排后）；
    /// - 同层内按“评分 + 随机扰动(0~3)”排序，评分高者期望更靠前，但每次结果不同。
    private func randomizedCarousel() -> [SeriesListDTO] {
        var seen = Set<Int64>()
        var withFanart: [SeriesListDTO] = []
        var withoutFanart: [SeriesListDTO] = []
        for group in groups {
            for item in group.allItems {
                guard !seen.contains(item.id) else { continue }
                seen.insert(item.id)
                if item.fanartUrl != nil {
                    withFanart.append(item)
                } else {
                    withoutFanart.append(item)
                }
            }
        }
        return weightedShuffle(withFanart) + weightedShuffle(withoutFanart)
    }

    /// 加权洗牌：评分决定“优势分”，叠加随机扰动后降序
    private func weightedShuffle(_ items: [SeriesListDTO]) -> [SeriesListDTO] {
        items
            .map { ($0, ($0.rating ?? 0) + Double.random(in: 0...3)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

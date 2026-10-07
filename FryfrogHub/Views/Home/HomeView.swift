import SwiftUI

/// 影视页显示方式（持久化，key "homeDisplayMode"）
private enum HomeDisplayMode: String {
    case grouped
    case overview
}

struct HomeView: View {
    @State private var service = HomeService.shared
    @State private var displayMode: HomeDisplayMode
    /// 分阶段切换：先隐藏标题（左移淡出），再显示总览网格（卡片飞行重组）
    @State private var showOverview = false
    @State private var hideTitles = false
    @State private var transitionTask: Task<Void, Never>?
    /// 总览网格数据缓存（避免 body 反复 flatMap+去重）
    @State private var overviewItems: [SeriesListDTO] = []
    /// matchedGeometry 命名空间：分库横排卡片 ↔ 总览网格卡片
    @Namespace private var transitionNamespace
    /// 轮播选中的条目（导航目标在 lazy 容器外挂载）
    @State private var selectedCarouselItem: SeriesListDTO?

    private var privacy: PrivacySettings { .shared }

    init() {
        let saved = UserDefaults.standard.string(forKey: "homeDisplayMode")
        let mode = HomeDisplayMode(rawValue: saved ?? "") ?? .grouped
        _displayMode = State(initialValue: mode)
        _showOverview = State(initialValue: mode == .overview)
        _hideTitles = State(initialValue: mode == .overview)
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.groups.isEmpty {
                    ProgressView("加载影视…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.groups.isEmpty {
                    ContentUnavailableView("暂无影视", systemImage: "play.rectangle", description: Text(service.errorMessage ?? "影视媒体库中没有可展示的内容"))
                } else {
                    ScrollView {
                        homeScrollContent
                    }
                    .scrollIndicators(.hidden)
                    // 轮播图区域全宽无圆角，从屏幕顶部沉浸展示（去掉会让内容整体下移、顶部露出固定色带）
                    .ignoresSafeArea(edges: .top)
                }
            }
            .background(Color.appBackground)
            // 轮播导航目标挂在 lazy 容器之外，避免 navigationDestination 在 LazyVStack 内被忽略
            .navigationDestination(item: $selectedCarouselItem) { item in
                SeriesDetailView(series: item) { _ in
                    // 收藏变化后由首页自行刷新，这里无需额外处理
                }
            }
            // 统一使用系统导航栏深色主题
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        Image(systemName: "heart")
                    }

                    NavigationLink {
                        CalendarView()
                    } label: {
                        Image(systemName: "calendar")
                    }

                    Menu {
                        Section("显示") {
                            // 系统勾选列表：仅选中项显示勾选，图标列统一预留（不跳变）
                            Picker("显示方式", selection: $displayMode) {
                                Text("分库显示").tag(HomeDisplayMode.grouped)
                                Text("总览显示").tag(HomeDisplayMode.overview)
                            }
                            .pickerStyle(.inline)
                        }
                        Section("维护") {
                            Button {
                                AuthImageLoader.shared.purgeAll()
                                Task {
                                    await service.fetchHomeContent()
                                }
                            } label: {
                                Label("刷新", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .task {
                await service.fetchHomeContent()
            }
            .refreshable {
                AuthImageLoader.shared.purgeAll()
                await service.fetchHomeContent()
            }
            .onChange(of: displayMode) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: "homeDisplayMode")
                if newValue == .overview {
                    // 预热总览首屏图片（动画期间下载，结束后不闪）
                    prewarmOverviewImages(count: 12)
                    // 阶段1：库标题向左消失（0.2s）
                    withAnimation(.easeInOut(duration: 0.2)) { hideTitles = true }
                    // 阶段2：总览网格出现，卡片经 matchedGeometry 飞行重组（0.35s）
                    transitionTask?.cancel()
                    transitionTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.35)) { showOverview = true }
                    }
                } else {
                    // 切回分库：分阶段——先卡片飞回横排，停顿后再标题从左侧回来
                    transitionTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.35)) { showOverview = false }
                    transitionTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)  // 飞行动画 + 间隔
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { hideTitles = false }
                    }
                }
            }
            .onChange(of: service.groups) { _, _ in
                rebuildOverviewItems()
            }
            .onChange(of: privacy.isEnabled) { _, _ in
                service.rollCarousel()
                rebuildOverviewItems()
            }
            .onAppear {
                rebuildOverviewItems()
            }
        }
    }

    private var homeScrollContent: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            carouselSection

            if !service.groups.isEmpty {
                overviewSection

                if !showOverview {
                    let shownLibraries = service.groups
                        .filter { $0.allItems.count > 0 || $0.name.isEmpty == false }
                        .filter { visible(group: $0) }
                    ForEach(shownLibraries) { group in
                        librarySection(group, hideTitle: hideTitles)
                    }
                    .transition(.opacity)
                } else {
                    overviewGrid
                }
            }
        }
    }

    /// 隐私模式下隐藏成人内容库
    private func visible(group: LibrarySeriesGroup) -> Bool {
        !privacy.isEnabled
            || group.allItems.contains { $0.isAdult == true } == false
    }

    /// 轮播图区域（全宽无圆角，从屏幕顶部沉浸展示）
    private var carouselSection: some View {
        let items = eligibleCarousel
        return Group {
            if !items.isEmpty {
                CarouselView(items: items) { selectedCarouselItem = $0 }
            }
        }
    }

    /// 轮播数据（隐私下过滤成人项）
    private var eligibleCarousel: [SeriesListDTO] {
        let all = service.carouselItems
        if privacy.isEnabled {
            return all.filter { $0.isAdult != true }
        }
        return all.prefix(10).map { $0 }
    }

    /// 总览统计行（轮播图与媒体库区块之间）：全部 / 电影 / 电视剧 / 其他
    private var overviewSection: some View {
        var seen = Set<Int64>()
        let items = service.groups
            .filter { visible(group: $0) }
            .flatMap(\.allItems)
            .filter { seen.insert($0.id).inserted }
        // 互斥划分，保证 电影 + 电视剧 + 其他 == 全部：
        // 独立视频且不是剧集 → 电影；mediaType=tv → 电视剧（含剧集库的孤立单集）；其余 → 其他
        let movies = items.filter { $0.isStandalone && !$0.isTV }.count
        let tv = items.filter(\.isTV).count
        let other = items.filter { !$0.isStandalone && !$0.isTV }.count

        return HStack(spacing: 12) {
            overviewItem(label: "全部", count: items.count)
            overviewItem(label: "电影", count: movies)
            overviewItem(label: "电视剧", count: tv)
            overviewItem(label: "其他", count: other)
        }
        .padding(.horizontal)
    }

    private func overviewItem(label: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 总览网格数据：按 id 去重 + 隐私过滤（缓存到 overviewItems，避免 body 反复计算）
    private func rebuildOverviewItems() {
        var seen = Set<Int64>()
        overviewItems = service.groups
            .filter { visible(group: $0) }
            .flatMap(\.allItems)
            .filter { seen.insert($0.id).inserted }
    }

    /// 预热总览前 N 张封面（fire-and-forget，命中 AuthImageLoader 缓存后网格显示不闪）
    private func prewarmOverviewImages(count: Int) {
        let urls = overviewItems.prefix(count).compactMap { ServerConnection.shared.imageURL(for: $0.coverUrl) }
        Task.detached(priority: .utility) {
            for url in urls {
                _ = try? await AuthImageLoader.shared.loadScaled(url: url)
            }
        }
    }

    /// 总览模式：全部内容大网格（卡片与分库模式共享 matchedGeometry id）
    private var overviewGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
            spacing: 16
        ) {
            ForEach(overviewItems) { item in
                NavigationLink {
                    SeriesDetailView(series: item) { _ in
                        Task { await service.fetchHomeContent() }
                    }
                } label: {
                    PosterCard(item: item)
                        .matchedGeometryEffect(id: "poster-\(item.id)", in: transitionNamespace)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        // 仅淡入：卡片位移由 matchedGeometry 飞行承担，容器整体滑入会让网格占位块
        // 从上方穿过飞行路径，在标题区形成黑色遮挡
        .transition(.opacity)
    }

    /// 单个媒体库区块（hideTitle=true 时标题随树移除，占位高度折叠，行上移到与总览网格对齐，
    /// 卡片不再需要飞越标题占位区；行内 PosterCard 的 matchedGeometry id 不变，飞行配对不受影响）
    private func librarySection(_ group: LibrarySeriesGroup, hideTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: hideTitle ? 0 : 12) {
            if !hideTitle {
                NavigationLink {
                    LibraryDetailView(group: group)
                } label: {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.title3.bold())
                            .foregroundStyle(Color.primary)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal)
                }
                // 覆盖 NavigationLink 默认的强调色(蓝)，保证标题/箭头始终为自适应主色
                .tint(.primary)
                // 左移+淡出（与旧属性动画一致的进出方向）
                .transition(.offset(x: -24).combined(with: .opacity))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(group.allItems) { item in
                        NavigationLink {
                            SeriesDetailView(series: item) { _ in
                                Task { await service.fetchHomeContent() }
                            }
                        } label: {
                            PosterCard(item: item)
                                .matchedGeometryEffect(id: "poster-\(item.id)", in: transitionNamespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    HomeView()
}

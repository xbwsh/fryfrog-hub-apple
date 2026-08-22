import SwiftUI

/// 首页显示方式（持久化，key "homeDisplayMode"）
private enum HomeDisplayMode: String {
    case grouped
    case overview
}

private enum HomeContentMode: String {
    case video
    case music
}

struct HomeView: View {
    @State private var service = HomeService.shared
    @State private var musicService = MusicService.shared
    @State private var displayMode: HomeDisplayMode
    @State private var contentMode: HomeContentMode
    /// 分阶段切换：先隐藏标题（左移淡出），再显示总览网格（卡片飞行重组）
    @State private var showOverview = false
    @State private var hideTitles = false
    @State private var transitionTask: Task<Void, Never>?
    /// 总览网格数据缓存（避免 body 反复 flatMap+去重）
    @State private var overviewItems: [SeriesListDTO] = []
    /// matchedGeometry 命名空间：分库横排卡片 ↔ 总览网格卡片
    @Namespace private var transitionNamespace

    private var privacy: PrivacySettings { .shared }

    init() {
        let saved = UserDefaults.standard.string(forKey: "homeDisplayMode")
        let mode = HomeDisplayMode(rawValue: saved ?? "") ?? .grouped
        _displayMode = State(initialValue: mode)
        _showOverview = State(initialValue: mode == .overview)
        _hideTitles = State(initialValue: mode == .overview)
        _contentMode = State(initialValue: HomeContentMode(
            rawValue: UserDefaults.standard.string(forKey: "homeContentMode") ?? ""
        ) ?? .video)
    }

    var body: some View {
        NavigationStack {
            Group {
                if contentMode == .video {
                    if service.isLoading && service.groups.isEmpty {
                        ProgressView("加载视频…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if service.groups.isEmpty {
                        ContentUnavailableView("暂无视频", systemImage: "play.rectangle", description: Text(service.errorMessage ?? "视频媒体库中没有可展示的内容"))
                    } else {
                        ScrollView {
                            homeScrollContent
                        }
                        .scrollIndicators(.hidden)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                } else if musicService.isLoading && musicService.groups.isEmpty {
                    ProgressView("加载音乐…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasMusicContent {
                    ContentUnavailableView("暂无音乐", systemImage: "music.note.list", description: Text(musicService.errorMessage ?? "音乐媒体库中没有可展示的内容"))
                } else {
                    ScrollView {
                        musicHomeScrollContent
                    }
                    .scrollIndicators(.hidden)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .background(Color.appBackground)
            .animation(.easeInOut(duration: 0.28), value: contentMode)
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
                        Section("首页内容") {
                            Picker("显示内容", selection: animatedContentModeBinding) {
                                Text("视频").tag(HomeContentMode.video)
                                Text("音乐").tag(HomeContentMode.music)
                            }
                            .pickerStyle(.inline)
                        }
                        if contentMode == .video {
                            Section("显示") {
                                // 系统勾选列表：仅选中项显示勾选，图标列统一预留（不跳变）
                                Picker("显示方式", selection: $displayMode) {
                                    Text("分库显示").tag(HomeDisplayMode.grouped)
                                    Text("总览显示").tag(HomeDisplayMode.overview)
                                }
                                .pickerStyle(.inline)
                            }
                        }
                        Section("维护") {
                            Button {
                                AuthImageLoader.shared.purgeAll()
                                Task {
                                    if contentMode == .music {
                                        await musicService.reload()
                                    } else {
                                        await service.fetchHomeContent()
                                    }
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
                await musicService.loadHome()
            }
            .refreshable {
                AuthImageLoader.shared.purgeAll()
                await service.fetchHomeContent()
                await musicService.reload()
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
            .onChange(of: contentMode) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: "homeContentMode")
                if newValue == .music {
                    Task { await musicService.loadHome() }
                } else {
                    Task { await service.fetchHomeContent() }
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

    private var musicHomeScrollContent: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            musicSection
        }
        .padding(.top, 12)
    }

    private var animatedContentModeBinding: Binding<HomeContentMode> {
        Binding(
            get: { contentMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.28)) {
                    contentMode = newValue
                }
            }
        )
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
                CarouselView(items: items)
            }
        }
    }

    private var hasMusicContent: Bool {
        musicService.groups.contains { !$0.albums.isEmpty || !$0.artists.isEmpty }
    }

    /// 首页音乐入口：音乐保持独立模块，不与视频卡片混排。
    private var musicSection: some View {
        let albums = musicService.groups
            .flatMap(\.albums)
            .reduce(into: [Int64: MusicAlbum]()) { result, album in
                result[album.id] = album
            }
            .values
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let artists = musicService.groups
            .flatMap(\.artists)
            .reduce(into: [Int64: MusicArtist]()) { result, artist in
                result[artist.id] = artist
            }.values
        let totalSongs = albums.reduce(0) { $0 + ($1.trackCount ?? 0) }

        let featured = albums.first
        return Group {
            if !albums.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Label("\(albums.count) 张专辑", systemImage: "square.stack")
                        Text("·").foregroundStyle(.tertiary)
                        Label("\(artists.count) 位歌手", systemImage: "person.2")
                        if totalSongs > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Label("\(totalSongs) 首", systemImage: "music.note")
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    if let featured {
                        NavigationLink { MusicAlbumView(album: featured) } label: {
                            HomeMusicHeroCard(album: featured)
                        }
                        .buttonStyle(.plain)
                    }

                    if !artists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("歌手")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(Array(artists.prefix(12))) { artist in
                                        NavigationLink { MusicArtistView(artist: artist) } label: {
                                            VStack(spacing: 6) {
                                                ServerImageView(path: artist.coverUrl)
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                                                Text(artist.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .frame(width: 70)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("专辑")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("最近 12 张").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(albums.prefix(12))) { album in
                                NavigationLink {
                                    MusicAlbumView(album: album)
                                } label: {
                                    HomeMusicListRow(album: album)
                                }
                                .buttonStyle(.plain)
                                if album.id != Array(albums.prefix(12)).last?.id {
                                    Divider().padding(.leading, 68).opacity(0.6)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal)
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

private struct HomeMusicListRow: View {
    let album: MusicAlbum

    var body: some View {
        HStack(spacing: 12) {
            ServerImageView(path: album.coverUrl)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(album.artistName ?? "未知歌手")
                        .lineLimit(1)
                    if let year = album.year {
                        Text("· \(String(year))")
                    } else if let genre = album.genre, !genre.isEmpty {
                        Text("· \(genre)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

private struct HomeMusicHeroCard: View {
    let album: MusicAlbum

    var body: some View {
        HStack(spacing: 14) {
            ServerImageView(path: album.coverUrl)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("精选专辑")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(album.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(album.artistName ?? "未知歌手")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = album.year { Text(String(year)) }
                    if let genre = album.genre, !genre.isEmpty { Text("· \(genre)") }
                    if let trackCount = album.trackCount { Text("· \(trackCount)首") }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor, in: Circle())
        }
        .padding(12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeMusicAlbumCard: View {
    let album: MusicAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ServerImageView(path: album.coverUrl)
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(album.artistName ?? "未知歌手")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 128, alignment: .leading)
    }
}

#Preview {
    HomeView()
}

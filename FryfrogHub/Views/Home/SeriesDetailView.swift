import SwiftUI

/// 视频详情页 —— 沉浸式横屏背景图 + 简介/演员/分季分集 + 播放入口
struct SeriesDetailView: View {
    let series: SeriesListDTO
    var onFavoriteChanged: ((Bool) -> Void)?
    /// 初始选中的季（追更日历跳转用；nil 时使用记忆的季）
    let initialSeason: Int?

    @State private var service = VideoService.shared
    @State private var favorite: Bool
    @State private var busyAction: String?
    @State private var actionError: String?
    @State private var playingVideo: VideoDTO?
    /// 分集展示模式（缩略图/列表），选择后持久记忆，无需每次重新切换
    @AppStorage("episodeDisplayMode") private var displayMode = EpisodeDisplayMode.grid
    /// 当前选中的季（按系列持久记忆）
    @State private var selectedSeasonNumber: Int?
    /// 维护弹窗
    @State private var showingMetadataEdit = false
    @State private var showingTmdbSearch = false
    @State private var showingUnbindConfirm = false
    @State private var showingCoverSelect = false
    @State private var showingLogoSelect = false

    init(series: SeriesListDTO, onFavoriteChanged: ((Bool) -> Void)? = nil, initialSeason: Int? = nil) {
        self.series = series
        self.onFavoriteChanged = onFavoriteChanged
        self.initialSeason = initialSeason
        _favorite = State(initialValue: series.favorite == true)
    }

    private var client: APIClient { .shared }

    /// 仅 ADMIN 显示管理类操作（后端同时强制 403 兜底）
    private var isAdmin: Bool { AuthService.shared.currentUser?.isAdmin == true }

    private var hasContent: Bool { service.detail != nil || service.movie != nil }

    var body: some View {
        baseContent
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .task { await load() }
            .fullScreenCover(item: $playingVideo) { video in
                VideoPlayerView(videoId: video.id, title: video.displayTitle, streamUrl: video.streamUrl)
            }
            // 播放器关闭后刷新进度/已看完状态
            .onChange(of: playingVideo) { _, newValue in
                guard newValue == nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await fetch()
                }
            }
            .sheet(isPresented: $showingMetadataEdit) {
                metadataEditSheet
            }
            .sheet(isPresented: $showingTmdbSearch) {
                tmdbSearchSheet
            }
            .sheet(isPresented: $showingCoverSelect) {
                coverSelectSheet
            }
            .sheet(isPresented: $showingLogoSelect) {
                logoSelectSheet
            }
            .confirmationDialog(
                "解绑 TMDB 元数据？",
                isPresented: $showingUnbindConfirm,
                titleVisibility: .visible
            ) {
                Button("解绑", role: .destructive) {
                    Task { await unbindTmdb() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("解绑后该视频（同标题系列）将清除 TMDB 元数据。")
            }
    }

    /// 主内容（加载/错误/详情滚动区）
    private var detailContent: some View {
        Group {
            if service.isLoading && !hasContent {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasContent {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(service.errorMessage ?? "无法加载详情")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heroHeader
                        infoSection
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await fetch() }
            }
        }
    }

    /// 内容 + 导航栏外观
    private var baseContent: some View {
        detailContent
            .ignoresSafeArea(edges: .top)
            .background(Color.appBackground)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        maintenanceMenu
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
    }

    // MARK: - 维护弹窗内容

    @ViewBuilder
    private var metadataEditSheet: some View {
        if let movie = service.movie {
            MetadataEditView(mode: .movie(movie)) {
                Task { await fetch() }
            }
        } else if let detail = service.detail {
            MetadataEditView(mode: .series(detail)) {
                Task { await fetch() }
            }
        }
    }

    @ViewBuilder
    private var tmdbSearchSheet: some View {
        if let tmdbVideoId {
            TmdbSearchView(videoId: tmdbVideoId) {
                Task { await fetch() }
            }
        }
    }

    @ViewBuilder
    private var coverSelectSheet: some View {
        if series.isStandalone {
            CoverSelectView(mode: .movie(videoId: series.id)) {
                Task { await fetch() }
            }
        } else if let videoId = selectedSeasonFirstEpisodeId {
            CoverSelectView(mode: .series(seriesId: series.id, videoId: videoId)) {
                Task { await fetch() }
            }
        }
    }

    @ViewBuilder
    private var logoSelectSheet: some View {
        if series.isStandalone {
            LogoSelectView(mode: .movie(videoId: series.id)) {
                Task { await fetch() }
            }
        } else {
            LogoSelectView(mode: .series(seriesId: series.id)) {
                Task { await fetch() }
            }
        }
    }

    // MARK: - 头部

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            ServerImageView(path: heroFanart)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                if let logo = heroLogo {
                    // 有字标 Logo（艺术字）时用它替代纯文本标题
                    ServerImageView(path: logo, contentMode: .fit)
                        .frame(width: 300, height: 96, alignment: .leading)
                        .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                } else {
                    Text(series.displayTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }

                HStack(spacing: 16) {
                    if !series.yearText.isEmpty {
                        Text(series.yearText)
                    }
                    Text(series.isTV ? "剧集" : "电影")
                    if let rating = detailRating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
            }
            .padding(20)
        }
        .frame(height: 260)
        .clipped()
    }

    private var heroLogo: String? {
        service.detail?.logoUrl ?? service.movie?.logoUrl ?? series.logoUrl
    }

    private var heroFanart: String? {
        service.detail?.fanartUrl ?? service.movie?.fanartUrl ?? series.fanartUrl
    }

    private var detailRating: Double? {
        service.detail?.rating ?? service.movie?.rating ?? series.rating
    }

    // MARK: - 信息区

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if series.isStandalone {
                moviePlaySection
                metaRow
            } else {
                metaRow
            }

            overviewSection
            actorsSection

            if !series.isStandalone {
                seasonsSection
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 电影独立播放按钮（带续播提示）
    @ViewBuilder
    private var moviePlaySection: some View {
        if let movie = service.movie {
            Button {
                MPVLog.log("movie play tapped id=\(movie.id)")
                playingVideo = movie
            } label: {
                Label(moviePlayLabel(for: movie), systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func moviePlayLabel(for movie: VideoDTO) -> String {
        if movie.isWatched {
            return "重新播放"
        }
        if let pct = movie.watchProgressPercent, pct > 1 {
            return "继续观看 · \(Int(pct))%"
        }
        return "播放"
    }

    /// 元信息行：电影显示时长/分辨率/格式/类型，剧集显示集数/季数/状态/分辨率
    private var metaRow: some View {
        HStack(spacing: 12) {
            if let movie = service.movie {
                if let minutes = movie.durationMinutes, minutes > 0 { Text("\(minutes) 分钟") }
                if let res = movie.resolutionLabel, !res.isEmpty { Text(res) }
                if let format = movie.format, !format.isEmpty { Text(format) }
                if let genre = movie.genre, !genre.isEmpty { Text(genre) }
            } else if let detail = service.detail {
                if let total = detail.totalEpisodes, total > 0 { Text("共 \(total) 集") }
                if let seasons = detail.numberOfSeasons, seasons > 0 { Text("共 \(seasons) 季") }
                if let status = detail.status, !status.isEmpty { Text(status) }
                if let resolutions = detail.resolutions, !resolutions.isEmpty {
                    Text(resolutions.joined(separator: " · "))
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = service.detail?.overview ?? service.movie?.overview, !overview.isEmpty {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: - 演员

    @ViewBuilder
    private var actorsSection: some View {
        if !service.actors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("演员")
                    .font(.title3.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(service.actors) { actor in
                            VStack(spacing: 6) {
                                ServerImageView(path: actor.avatarPath)
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                Text(actor.displayName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if !actor.characterText.isEmpty {
                                    Text(actor.characterText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 88)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 分季分集

    @ViewBuilder
    private var seasonsSection: some View {
        if let seasons = service.detail?.seasons, !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("分集")
                        .font(.title3.bold())
                    Spacer()
                    Picker("展示方式", selection: $displayMode) {
                        ForEach(EpisodeDisplayMode.allCases) { mode in
                            Image(systemName: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // 季切换标签（单季直接显示，无需标签行）
                if seasons.count > 1 {
                    seasonTabRow(seasons)
                }

                // 只展示选中季的剧集
                if let season = selectedSeason(in: seasons) {
                    let episodes = season.episodes ?? []
                    if !episodes.isEmpty {
                        switch displayMode {
                        case .grid:
                            episodeGrid(episodes)
                        case .numbers:
                            episodeNumberGrid(episodes)
                        case .list:
                            episodeList(episodes)
                        }
                    }
                }
            }
        }
    }

    /// 季切换标签行（横向滚动，自动滚动到选中季）
    private func seasonTabRow(_ seasons: [SeasonDTO]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        let number = season.seasonNumber ?? 0
                        let isSelected = number == (selectedSeason(in: seasons)?.seasonNumber ?? 0)
                        Button {
                            selectSeason(season)
                        } label: {
                            Text(season.seasonLabel)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? Color.accentColor : Color.appSurface,
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .id(number)
                    }
                }
                // 进入页面或选中季变化时，滚动让选中季保持在可视区中间
                .onAppear {
                    scrollToSelected(in: seasons, using: proxy)
                }
                .onChange(of: selectedSeasonNumber) { _, _ in
                    scrollToSelected(in: seasons, using: proxy)
                }
            }
        }
    }

    private func scrollToSelected(in seasons: [SeasonDTO], using proxy: ScrollViewProxy) {
        guard let season = selectedSeason(in: seasons) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(season.seasonNumber ?? 0, anchor: .center)
        }
    }

    /// 解析当前选中季；无记录或季数变化时回退到第一季
    private func selectedSeason(in seasons: [SeasonDTO]) -> SeasonDTO? {
        if let number = selectedSeasonNumber,
           let match = seasons.first(where: { ($0.seasonNumber ?? 0) == number }) {
            return match
        }
        return seasons.first
    }

    private func selectSeason(_ season: SeasonDTO) {
        let number = season.seasonNumber ?? 0
        selectedSeasonNumber = number
        UserDefaults.standard.set(number, forKey: "selectedSeason-\(series.id)")
    }

    /// 分集列表模式（紧凑行）
    private func episodeList(_ episodes: [VideoDTO]) -> some View {
        VStack(spacing: 0) {
            ForEach(episodes) { episode in
                episodeRow(episode)
                if episode.id != episodes.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 分集缩略图网格模式（16:9 封面多列排列，显著减少纵向滚动）
    private func episodeGrid(_ episodes: [VideoDTO]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            ForEach(episodes) { episode in
                episodeTile(episode)
            }
        }
    }

    /// 分集数字方块模式（正方形，仅显示集数，剧集很多时最紧凑）
    private func episodeNumberGrid(_ episodes: [VideoDTO]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                episodeNumberTile(episode, number: episode.episodeNumber ?? index + 1)
            }
        }
    }

    private func episodeNumberTile(_ episode: VideoDTO, number: Int) -> some View {
        Button {
            MPVLog.log("episode tapped id=\(episode.id)")
            playingVideo = episode
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(episode.isWatched ? Color.green.opacity(0.85) : Color.appSurface)

                Text("\(number)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(episode.isWatched ? .white : .primary)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let pct = episode.watchProgressPercent, pct > 0, !episode.isWatched {
                    ProgressView(value: min(pct, 100) / 100)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(height: 3)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func episodeTile(_ episode: VideoDTO) -> some View {
        Button {
            MPVLog.log("episode tapped id=\(episode.id)")
            playingVideo = episode
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 用横屏背景图而非竖屏封面：每集独立生成、各不相同，且天然是 16:9
                ServerImageView(path: episode.fanartUrl)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    if !episode.episodeLabel.isEmpty {
                        Text(episode.episodeLabel)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                    Text(episode.displayTitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)

                if episode.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if let pct = episode.watchProgressPercent, pct > 0, !episode.isWatched {
                    ProgressView(value: min(pct, 100) / 100)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(_ episode: VideoDTO) -> some View {
        Button {
            MPVLog.log("episode tapped id=\(episode.id)")
            playingVideo = episode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(
                            episode.isWatched
                                ? Color.green
                                : (progress(of: episode) > 0 ? Color.accentColor : Color.secondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if !episode.episodeLabel.isEmpty {
                                Text(episode.episodeLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(episode.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        if !episode.durationText.isEmpty {
                            Text(episode.durationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !episode.isWatched {
                        let pct = progress(of: episode)
                        if pct > 0 {
                            Text("\(pct)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let pct = episode.watchProgressPercent, pct > 0, !episode.isWatched {
                    ProgressView(value: min(pct, 100) / 100)
                        .tint(Color.accentColor)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func progress(of episode: VideoDTO) -> Int {
        guard let pct = episode.watchProgressPercent, pct.isFinite else { return 0 }
        return min(Int(pct.rounded()), 100)
    }

    // MARK: - 菜单项

    /// 右上角维护菜单（拆成独立子表达式，避免编译器类型检查超时）
    @ViewBuilder
    private var maintenanceMenu: some View {
        favoriteButton
        if isAdmin {
            Divider()
            Section("维护") {
                if let _ = tmdbVideoId {
                    Button {
                        showingTmdbSearch = true
                    } label: {
                        Label("搜索并绑定 TMDB", systemImage: "magnifyingglass")
                    }

                    Button {
                        Task { await refreshMetadata() }
                    } label: {
                        Label("刷新元数据", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if coverSelectAvailable {
                    Button {
                        showingCoverSelect = true
                    } label: {
                        Label("设置封面", systemImage: "photo")
                    }
                }

                Button {
                    showingMetadataEdit = true
                } label: {
                    Label("编辑元数据", systemImage: "pencil")
                }

                if series.isTV {
                    Button {
                        Task { await refreshSeasonCovers() }
                    } label: {
                        Label("刷新季海报", systemImage: "photo.on.rectangle.angled")
                    }
                }

                Button {
                    Task { await refreshLogo() }
                } label: {
                    Label("补全 Logo", systemImage: "character.book.closed")
                }

                Button {
                    showingLogoSelect = true
                } label: {
                    Label("手动设置 Logo", systemImage: "character.book.closed.fill")
                }

                if isTmdbBound {
                    Button(role: .destructive) {
                        showingUnbindConfirm = true
                    } label: {
                        Label("解绑 TMDB", systemImage: "link.badge.minus")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Label(
                favorite ? "取消收藏" : "收藏",
                systemImage: favorite ? "heart.slash" : "heart"
            )
        }
    }

    // MARK: - 数据加载

    private func load() async {
        service.reset()
        selectedSeasonNumber = initialSeason
            ?? UserDefaults.standard.object(forKey: "selectedSeason-\(series.id)") as? Int
        await fetch()
    }

    private func fetch() async {
        await service.load(id: series.id, isStandalone: series.isStandalone)
        await service.loadActors(id: series.id)
    }

    // MARK: - 操作

    /// TMDB 相关操作所用的视频 ID：电影用自身 ID，剧集用第一集 ID（绑定/刷新作用于整个同标题系列）
    private var tmdbVideoId: Int64? {
        if series.isStandalone {
            return series.id
        }
        return service.detail?.allEpisodes.first?.id
    }

    /// 是否已绑定 TMDB（决定是否显示"解绑"）
    private var isTmdbBound: Bool {
        (service.movie?.tmdbId ?? service.detail?.tmdbId) != nil
    }

    /// 设置封面是否可用：电影始终可用；剧集需要有剧集才能截帧
    private var coverSelectAvailable: Bool {
        series.isStandalone || selectedSeasonFirstEpisodeId != nil
    }

    /// 当前选中季的第一集 ID（剧集设置封面用其截帧）
    private var selectedSeasonFirstEpisodeId: Int64? {
        guard let seasons = service.detail?.seasons else { return nil }
        return selectedSeason(in: seasons)?.episodes?.first?.id
    }

    private func favoritePath() -> String {
        series.isStandalone ? "/api/v1/video/\(series.id)/favorite" : "/api/v1/video/series/\(series.id)/favorite"
    }

    private func toggleFavorite() async {
        guard busyAction == nil else { return }
        busyAction = "favorite"
        defer { busyAction = nil }

        let newStatus = !favorite
        do {
            let _: ApiResponse<SeriesListDTO> = try await client.request(
                favoritePath(),
                method: "PUT",
                queryItems: [URLQueryItem(name: "status", value: String(newStatus))]
            )
            favorite = newStatus
            onFavoriteChanged?(newStatus)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 刷新 TMDB 元数据（异步：重新搜索绑定 + 重命名文件）
    private func refreshMetadata() async {
        guard busyAction == nil, let videoId = tmdbVideoId else { return }
        busyAction = "metadata"
        defer { busyAction = nil }

        do {
            try await service.refreshTmdb(videoId: videoId)
            purgeDetailImages()
            await fetch()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func refreshSeasonCovers() async {
        guard busyAction == nil else { return }
        busyAction = "seasonCovers"
        defer { busyAction = nil }

        do {
            let _: ApiResponse<[String: String]> = try await client.request(
                "/api/v1/video/series/\(series.id)/refresh-season-covers",
                method: "POST"
            )
            purgeDetailImages()
            await fetch()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 解绑 TMDB 元数据
    private func unbindTmdb() async {
        guard busyAction == nil, let videoId = tmdbVideoId else { return }
        busyAction = "unbind"
        defer { busyAction = nil }

        do {
            try await service.unbindTmdb(videoId: videoId)
            purgeDetailImages()
            await fetch()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 补全 Logo（电影 / 系列各自接口）
    private func refreshLogo() async {
        guard busyAction == nil else { return }
        busyAction = "logo"
        defer { busyAction = nil }

        do {
            if series.isTV {
                try await service.refreshSeriesLogo(id: series.id)
            } else {
                try await service.refreshMovieLogo(id: series.id)
            }
            purgeDetailImages()
            await fetch()
        } catch {
            actionError = error.localizedDescription
        }
    }
/// 清空详情页相关图片缓存（封面/横屏背景/演员头像），让刷新后的图片立即生效
    private func purgeDetailImages() {
        AuthImageLoader.shared.purge(path: series.coverUrl)
        AuthImageLoader.shared.purge(path: series.fanartUrl)
        for actor in service.actors {
            AuthImageLoader.shared.purge(path: actor.avatarPath)
        }
    }
}

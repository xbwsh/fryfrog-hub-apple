import SwiftUI

/// 演员详情页（GET /api/v1/video/actor/{actorId} + /works）
/// 并行加载详情与作品列表：头像/个人信息/简介/知名作品横滑 + 作品网格分页。
/// 演员不存在（404）时显示错误提示；存在但无作品（200 空列表）时显示空态。
struct ActorWorksView: View {
    let actor: VideoActor

    @State private var detail: ActorDetailDTO?
    @State private var items: [SeriesListDTO] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var nextPage = 0
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var bioExpanded = false
    @State private var castExpanded = false

    private var privacy: PrivacySettings { .shared }
    private var isAdmin: Bool { AuthService.shared.currentUser?.isAdmin == true }

    var body: some View {
        Group {
            if isLoading && detail == nil && items.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, detail == nil && items.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        actorHeader
                        if let bio = detail?.biography, !bio.isEmpty {
                            biographySection(bio)
                        }
                        if !filtered(knownFor).isEmpty {
                            knownForSection
                        }
                        if !filtered(cast).isEmpty {
                            allCastSection
                        }
                        worksSection
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(actor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshDetail() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .accessibilityLabel("刷新演员信息")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 头部

    private var actorHeader: some View {
        HStack(spacing: 14) {
            ServerImageView(path: avatarPath)
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(actor.displayName)
                    .font(.title2.bold())
                if !infoText.isEmpty {
                    Text(infoText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(totalCount) 部作品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - 简介（可展开）

    private func biographySection(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(.title3.bold())
            Text(bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .lineLimit(bioExpanded ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { bioExpanded.toggle() }
            } label: {
                Text(bioExpanded ? "收起" : "展开")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 知名作品横滑

    private var knownForSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("知名作品")
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(filtered(knownFor)) { item in
                        NavigationLink {
                            SeriesDetailView(series: item)
                        } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 全部出演（可展开）

    private var allCastSection: some View {
        let cast = filtered(cast)
        return VStack(alignment: .leading, spacing: 10) {
            Text("全部出演")
                .font(.title3.bold())
            let shown = castExpanded ? cast : Array(cast.prefix(6))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 20) {
                ForEach(shown) { item in
                    NavigationLink {
                        SeriesDetailView(series: item)
                    } label: {
                        PosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            if cast.count > 6 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { castExpanded.toggle() }
                } label: {
                    Text(castExpanded ? "收起" : "展开全部（\(cast.count) 部）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 作品网格（分页）

    @ViewBuilder
    private var worksSection: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("作品")
                    .font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink {
                            SeriesDetailView(series: item)
                        } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if hasMore {
                    footerView
                        .onAppear { Task { await loadMore() } }
                }
            }
        } else {
            ContentUnavailableView(
                "暂无作品",
                systemImage: "film",
                description: Text("该演员暂时没有可显示的作品")
            )
            .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            Button {
                Task { await loadMore() }
            } label: {
                Text("加载更多")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - 数据

    private var avatarPath: String {
        detail?.imageUrl ?? actor.avatarPath
    }

    private var infoText: String {
        detail?.infoText ?? ""
    }

    private var knownFor: [SeriesListDTO] {
        detail?.knownFor ?? []
    }

    private var cast: [SeriesListDTO] {
        detail?.credits?.cast ?? []
    }

    /// 隐私过滤 + 按 id 去重（同一系列可能在 cast/knownFor/works 中重复出现，
    /// ForEach 依赖唯一 id，重复会导致 undefined results 警告）
    private func filtered(_ list: [SeriesListDTO]) -> [SeriesListDTO] {
        var seen = Set<Int64>()
        return list
            .filter { !privacy.isEnabled || $0.isAdult != true }
            .filter { seen.insert($0.id).inserted }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let detailTask = VideoService.shared.fetchActorDetail(actorId: actor.id)
            async let worksTask = VideoService.shared.fetchActorWorks(actorId: actor.id, page: 0)
            do {
                detail = try await detailTask
            } catch {
                // 详情失败但作品仍可展示（如 TMDB 首次拉取未完成）：不阻断作品列表
                AppLog.networking.warning("演员详情加载失败 id=\(actor.id): \(AppLog.describe(error))")
            }
            do {
                let page = try await worksTask
                apply(page, replace: true)
            } catch {
                if detail == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await VideoService.shared.fetchActorWorks(actorId: actor.id, page: nextPage)
            apply(page, replace: false)
        } catch {
            // 加载更多失败保留已加载内容，静默（下拉可重试）
        }
    }

    private func refreshDetail() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await VideoService.shared.refreshActor(actorId: actor.id)
            GlobalNotice.shared.show("已请求刷新，稍后下拉更新")
        } catch {
            GlobalNotice.shared.show("刷新失败：\(error.localizedDescription)")
        }
    }

    private func apply(_ page: PageResponse<SeriesListDTO>, replace: Bool) {
        var works = filtered(page.content ?? [])
        items = replace ? works : items + works
        nextPage = (page.page ?? 0) + 1
        hasMore = (page.totalPages ?? 0) > (page.page ?? 0) + 1
        totalCount = Int(page.totalElements ?? 0)
        if replace { errorMessage = nil }
    }
}

#Preview {
    NavigationStack {
        ActorWorksView(actor: VideoActor(id: 1, createdAt: nil, updatedAt: nil, name: "刘德华", character: nil, sourceActorId: nil, imageUrl: nil))
    }
}
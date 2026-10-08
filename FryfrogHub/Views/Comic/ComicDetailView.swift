import SwiftUI

/// 漫画详情页
struct ComicDetailView: View {
    let comicId: Int64
    // 独立实例：共用单例时 selectedComic 残留上一本书——新书加载中/失败都会渲染旧书
    // （错误分支因 comic 非空永远走不到），且"开始阅读"会拿着旧书进入阅读器
    @State private var service = ComicService()
    @State private var showingMarkCompleted = false
    @State private var showingUnbind = false
    @State private var showingScrape = false
    @State private var readingTarget: ReadingTarget?

    /// 进入阅读器的起始位置（nil = 继续上次进度）
    struct ReadingTarget: Hashable {
        let chapterIndex: Int
        let pageIndex: Int
    }

    private var comic: ComicDetailDTO? { service.selectedComic }

    var body: some View {
        Group {
            if service.isLoading && comic == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let comic = comic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(comic: comic)

                        if let overview = comic.overview, !overview.isEmpty {
                            overviewSection(overview)
                        }

                        if let progress = comic.progress {
                            progressSection(progress)
                        }

                        if let chapters = comic.chapters, !chapters.isEmpty {
                            chaptersSection(chapters, comic: comic)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .navigationTitle(comic.title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let chapters = comic.chapters, !chapters.isEmpty {
                        startReadingButton(chapters: chapters, progress: comic.progress)
                    }
                }
            } else {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(service.errorMessage ?? "请稍后重试")
                )
            }
        }
        .background(Color.appBackground)
        .task {
            await service.loadComicDetail(id: comicId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let comic = comic {
                        Button {
                            showingMarkCompleted = true
                        } label: {
                            Label(
                                comic.progress?.completed == true ? "标记为未读完" : "标记为已读完",
                                systemImage: comic.progress?.completed == true ? "xmark.circle" : "checkmark.circle"
                            )
                        }

                        if comic.progress != nil {
                            Button(role: .destructive) {
                                Task {
                                    try? await service.deleteProgress(id: comicId)
                                    await service.loadComicDetail(id: comicId)
                                }
                            } label: {
                                Label("清除进度", systemImage: "trash")
                            }
                        }

                        if AuthService.shared.currentUser?.isAdmin == true {
                            Button {
                                showingScrape = true
                            } label: {
                                Label("重新刮削", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        if AuthService.shared.currentUser?.isAdmin == true,
                           comic.metadataSource == "scrape" {
                            Button(role: .destructive) {
                                showingUnbind = true
                            } label: {
                                Label("解绑刮削元数据", systemImage: "link.badge.plus")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingScrape) {
            ComicScrapeView(comicId: comicId, initialQuery: comic?.title ?? "") {
                Task { await service.loadComicDetail(id: comicId) }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { readingTarget != nil },
            set: { if !$0 { readingTarget = nil } }
        )) {
            if let comic = comic, let target = readingTarget {
                ComicReaderView(comic: comic, target: target)
            }
        }
        .alert("解绑刮削元数据", isPresented: $showingUnbind) {
            Button("取消", role: .cancel) {}
            Button("解绑", role: .destructive) {
                Task {
                    try? await service.unbind(id: comicId)
                    await service.loadComicDetail(id: comicId)
                }
            }
        } message: {
            Text("将清除刮削绑定标记，已写入的书名、作者、简介等字段会保留。")
        }
        .alert("标记读完", isPresented: $showingMarkCompleted) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                Task {
                    let completed = comic?.progress?.completed != true
                    try? await service.setCompleted(id: comicId, completed: completed)
                    await service.loadComicDetail(id: comicId)
                }
            }
        } message: {
            if let comic = comic {
                if comic.progress?.completed == true {
                    Text("确定要将「\(comic.title)」标记为未读完吗？")
                } else {
                    Text("确定要将「\(comic.title)」标记为已读完吗？")
                }
            }
        }
    }

    // MARK: - 动作

    private func startReading(chapters: [ComicDetailDTO.ChapterDTO], progress: ComicDetailDTO.ProgressDTO?) {
        var chapterIndex = progress?.chapterIndex ?? 0
        var pageIndex = progress?.pageIndex ?? 0
        // 进度越界保护
        if chapters.isEmpty { return }
        if chapterIndex >= chapters.count { chapterIndex = 0; pageIndex = 0 }
        let pageCount = chapters[chapterIndex].pageCount ?? 0
        if pageIndex >= pageCount { pageIndex = 0 }
        readingTarget = ReadingTarget(chapterIndex: chapterIndex, pageIndex: pageIndex)
    }

    // MARK: - 视图片段

    @ViewBuilder
    private func startReadingButton(chapters: [ComicDetailDTO.ChapterDTO],
                                    progress: ComicDetailDTO.ProgressDTO?) -> some View {
        let started = (progress?.chapterIndex ?? 0) > 0
        Button {
            startReading(chapters: chapters, progress: progress)
        } label: {
            Label(started ? "继续阅读" : "开始阅读", systemImage: "book")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func headerSection(comic: ComicDetailDTO) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: comic.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "book")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(comic.title)
                    .font(.title3.weight(.semibold))

                if let author = comic.author {
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let total = comic.totalChapters {
                        Label("\(total) 卷", systemImage: "books.vertical")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pubYear = comic.pubYear {
                        Label(String(pubYear), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let rating = comic.rating {
                    Label(String(format: "★ %.1f", rating), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let series = comic.series {
                    Label(comic.seriesPart.map { "\(series) #\($0)" } ?? series,
                          systemImage: "square.stack.3d.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(.headline)
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    @ViewBuilder
    private func progressSection(_ progress: ComicDetailDTO.ProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("阅读进度")
                    .font(.headline)
                Spacer()
                if let percent = progress.progressPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = progress.progressPercent {
                ProgressView(value: percent, total: 100)
                    .tint(progress.completed == true ? .green : .blue)
            }
        }
    }

    @ViewBuilder
    private func chaptersSection(_ chapters: [ComicDetailDTO.ChapterDTO],
                                 comic: ComicDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("卷/话")
                .font(.headline)
            ForEach(chapters, id: \.id) { chapter in
                Button {
                    readingTarget = ReadingTarget(
                        chapterIndex: chapter.chapterIndex,
                        pageIndex: 0
                    )
                } label: {
                    HStack {
                        Text(chapter.title ?? "第\(chapter.chapterIndex + 1)话")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if let pages = chapter.pageCount {
                            Text("\(pages) 页")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

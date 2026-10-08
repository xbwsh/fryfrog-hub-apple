import SwiftUI

/// 漫画阅读器：纵向滚动（默认）/横向翻页双模式（对齐 Android 端），按卷切换，页图走签名 URL，进度逐页上报
struct ComicReaderView: View {
    let comic: ComicDetailDTO
    let target: ComicDetailView.ReadingTarget

    @Environment(\.dismiss) private var dismiss

    @State private var chapterIndex: Int
    @State private var currentPageIndex: Int
    @State private var pageURLs: [URL] = []
    @State private var isLoadingPages = false
    @State private var loadErrorMessage: String?
    @State private var lastReported: (Int, Int) = (-1, -1)

    /// 阅读方向：默认纵向连续滚动（对齐 Android 端），顶栏可切换；不持久化，每次进入复位
    @State private var readingVertical = true
    /// 纵向模式下当前置顶页 id（scrollPosition 跟踪）
    @State private var scrollID: Int?

    /// 每卷起始的全局进度位置（用于顶部百分比显示）
    private var chapters: [ComicDetailDTO.ChapterDTO] { comic.chapters ?? [] }

    init(comic: ComicDetailDTO, target: ComicDetailView.ReadingTarget) {
        self.comic = comic
        self.target = target
        _chapterIndex = State(initialValue: target.chapterIndex)
        _currentPageIndex = State(initialValue: target.pageIndex)
    }

    var body: some View {
        Group {
            if isLoadingPages {
                ProgressView("加载页图…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = loadErrorMessage {
                ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark",
                                       description: Text(message))
            } else if pageURLs.isEmpty {
                ContentUnavailableView("没有页图", systemImage: "photo")
            } else {
                pageReader
            }
        }
        .background(Color.black)
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(topBarText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    readingVertical.toggle()
                } label: {
                    Image(systemName: readingVertical ? "arrow.up.and.down" : "arrow.left.and.right")
                }
                .accessibilityLabel(readingVertical ? "切换为翻页" : "切换为滚动")
            }
        }
        .task(id: chapterIndex) {
            await loadPages()
        }
        .onDisappear {
            reportNow()
        }
    }

    // MARK: - 翻页视图

    private var pageReader: some View {
        VStack(spacing: 0) {
            Group {
                if readingVertical {
                    verticalReader
                } else {
                    horizontalReader
                }
            }
            .onChange(of: currentPageIndex) { _, _ in
                reportProgress()
                prefetch(around: currentPageIndex)
            }

            // 章节切换
            HStack {
                Button {
                    if chapterIndex > 0 {
                        chapterIndex -= 1
                        currentPageIndex = 0
                    }
                } label: {
                    Image(systemName: "chevron.left")
                    Text("上一卷")
                }
                .disabled(chapterIndex <= 0)

                Spacer()

                Text(chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    if chapterIndex < chapters.count - 1 {
                        chapterIndex += 1
                        currentPageIndex = 0
                    }
                } label: {
                    Text("下一卷")
                    Image(systemName: "chevron.right")
                }
                .disabled(chapterIndex >= chapters.count - 1)
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    /// 横向翻页（左右滑动）
    private var horizontalReader: some View {
        TabView(selection: $currentPageIndex) {
            ForEach(pageURLs.indices, id: \.self) { index in
                pageView(at: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black)
    }

    /// 纵向连续滚动（上下滑动，对齐 Android 端 readerModeScroll：页间距 + 45% 焦点线选页）
    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(pageURLs.indices, id: \.self) { index in
                        pageView(at: index)
                            .id(index)
                    }
                }
            }
            .background(Color.black)
            .scrollPosition(id: $scrollID, anchor: UnitPoint(x: 0.5, y: 0.45))
            .onChange(of: scrollID) { _, newID in
                guard let newID, newID != currentPageIndex,
                      pageURLs.indices.contains(newID) else { return }
                currentPageIndex = newID
            }
            .onAppear {
                proxy.scrollTo(currentPageIndex, anchor: .top)
            }
            .onChange(of: pageURLs) { _, _ in
                proxy.scrollTo(currentPageIndex, anchor: .top)
            }
        }
    }

    private func pageView(at index: Int) -> some View {
        AsyncImage(url: pageURLs[index]) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var chapterTitle: String {
        let chapter = chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil
        return chapter?.title ?? "第\(chapterIndex + 1)话"
    }

    private var topBarText: String {
        let pageCount = pageURLs.count
        let globalPercent = globalPercentText
        return "\(chapterIndex + 1)/\(chapters.count)卷 · \(currentPageIndex + 1)/\(pageCount)页 · \(globalPercent)"
    }

    private var globalPercentText: String {
        guard let percent = percentOf(chapterIndex: chapterIndex, pageIndex: currentPageIndex) else {
            return ""
        }
        return String(format: "%.0f%%", percent)
    }

    // MARK: - 数据加载

    private func loadPages() async {
        guard chapters.indices.contains(chapterIndex) else { return }
        let chapterId = chapters[chapterIndex].id
        isLoadingPages = true
        loadErrorMessage = nil
        defer { isLoadingPages = false }
        do {
            let response: ApiResponse<[String]> = try await APIClient.shared.request(
                "/api/v1/comics/chapters/\(chapterId)/pages"
            )
            let paths = response.data ?? []
            pageURLs = paths.compactMap { ServerConnection.shared.imageURL(for: $0) }
            prefetch(around: 0)
            // 恢复到目标页
            if currentPageIndex >= pageURLs.count {
                currentPageIndex = max(0, pageURLs.count - 1)
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    /// 预取当前页前后各一页到图片加载器：翻页时相邻页直接命中内存缓存，避免转圈
    private func prefetch(around index: Int) {
        guard pageURLs.indices.contains(index) else { return }
        let window = (max(0, index - 1)...min(pageURLs.count - 1, index + 1))
        for i in window {
            let url = pageURLs[i]
            Task { @MainActor in
                _ = try? await AuthImageLoader.shared.loadScaled(url: url)
            }
        }
    }

    // MARK: - 进度

    /// 全局百分比：已完成卷页数 + 当前卷内页占比，除以总页数（与后端换算一致）
    private func percentOf(chapterIndex: Int, pageIndex: Int) -> Double? {
        let total = chapters.reduce(0) { $0 + ($1.pageCount ?? 0) }
        guard total > 0 else { return nil }
        var done = 0
        for chapter in chapters where chapter.chapterIndex < chapterIndex {
            done += chapter.pageCount ?? 0
        }
        if chapters.indices.contains(chapterIndex) {
            let pages = chapters[chapterIndex].pageCount ?? 0
            done += min(pages, pageIndex + 1)
        }
        return min(100, Double(done) / Double(total) * 100)
    }

    private func reportProgress() {
        // 翻页频率低，逐页上报
        guard lastReported != (chapterIndex, currentPageIndex) else { return }
        reportNow()
    }

    private func reportNow() {
        lastReported = (chapterIndex, currentPageIndex)
        let chapter = chapterIndex
        let page = currentPageIndex
        Task {
            try? await ComicService.shared.updateProgress(
                id: comic.id, chapterIndex: chapter, pageIndex: page
            )
        }
    }
}

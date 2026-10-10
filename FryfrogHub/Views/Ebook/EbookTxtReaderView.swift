import SwiftUI

/// TXT 在线阅读器：单章竖排滚动正文，章节目录分页懒加载（对齐 Android 端）。
/// 不下载整本书——正文/目录分别走 /content 与 /chapters（分页）接口，
/// 进度按 (全局章序 + 章内滚动比例) 换算整书百分比交给父视图节流上报。
struct EbookTxtReaderView: View {
    let book: EbookDetailDTO
    /// (整书百分比, 全局章序)——上报节流由父视图负责
    let onProgress: (Double, Int?) -> Void

    /// 当前章全局序号（恢复自阅读进度）
    @State private var chapterIndex: Int
    /// 已加载的章节目录项（key 为全局序号）
    @State private var chaptersByIndex: [Int: EbookChapterDTO] = [:]
    @State private var loadedPages: Set<Int> = []
    @State private var loadingPages: Set<Int> = []
    /// 全书总章数（详情 totalChapters 优先，目录页 totalElements 兜底）
    @State private var totalChapters: Int
    @State private var chapterText = ""
    @State private var isLoadingContent = false
    @State private var loadErrorMessage: String?
    @State private var showChapterSheet = false
    @State private var scrollFraction: Double = 0
    /// 正文内容总高 / 滚动视口高 / 当前内容顶部偏移（滚动距离 = -topOffset）
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var contentTopOffset: CGFloat = 0

    /// 一页目录条数（与后端 clamp_paging 上限对齐）
    private let pageSize = 300

    init(book: EbookDetailDTO, onProgress: @escaping (Double, Int?) -> Void) {
        self.book = book
        self.onProgress = onProgress
        _chapterIndex = State(initialValue: max(0, book.progress?.chapterIndex ?? 0))
        _totalChapters = State(initialValue: book.totalChapters ?? 0)
    }

    var body: some View {
        Group {
            if isLoadingContent && chapterText.isEmpty {
                ProgressView("加载正文…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = loadErrorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await bootstrap() }
                    }
                }
            } else {
                reader
            }
        }
        .background(Color.appBackground)
        .task { await bootstrap() }
        .sheet(isPresented: $showChapterSheet) {
            chapterSheet
        }
    }

    // MARK: - 正文

    private var reader: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chapterText.isEmpty ? "本章无内容" : chapterText)
                            .font(.system(size: 17))
                            .lineSpacing(6)
                            .foregroundStyle(chapterText.isEmpty ? .secondary : .primary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(key: ContentHeightKey.self, value: geo.size.height)
                                        .preference(
                                            key: ContentTopOffsetKey.self,
                                            value: geo.frame(in: .named("txtScroll")).minY
                                        )
                                }
                            )
                    }
                    .id("top")
                }
                .coordinateSpace(name: "txtScroll")
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ViewportHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
                .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
                .onPreferenceChange(ContentTopOffsetKey.self) { offset in
                    contentTopOffset = offset
                    updateScrollFraction()
                }
                .onChange(of: chapterIndex) { _, _ in
                    proxy.scrollTo("top", anchor: .top)
                }
            }

            if totalChapters > 1 {
                chapterBar
            }
        }
    }

    private func updateScrollFraction() {
        guard contentHeight > 0, viewportHeight > 0 else { return }
        let maxScroll = contentHeight - viewportHeight
        // 内容顶部相对视口的偏移：未滚动时 ≈0，向下滚动为负
        scrollFraction = maxScroll > 0 ? min(1, max(0, Double(-contentTopOffset / maxScroll))) : 0
        report()
    }

    /// 顶栏/底部栏之外的章务控制：上一章、当前章信息、目录、下一章
    private var chapterBar: some View {
        HStack {
            Button {
                Task { await goToChapter(chapterIndex - 1) }
            } label: {
                Label("上一章", systemImage: "chevron.left")
            }
            .disabled(chapterIndex <= 0)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showChapterSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                Text(chapterTitle(chapterIndex) + " · \(chapterIndex + 1)/\(totalChapters)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await goToChapter(chapterIndex + 1) }
            } label: {
                Text("下一章")
                Image(systemName: "chevron.right")
            }
            .disabled(chapterIndex >= totalChapters - 1)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: - 章节目录

    private var chapterSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<max(totalChapters, 0), id: \.self) { idx in
                        Button {
                            showChapterSheet = false
                            Task { await goToChapter(idx) }
                        } label: {
                            HStack {
                                Text(chapterTitle(idx))
                                    .font(.subheadline)
                                    .foregroundStyle(idx == chapterIndex ? Color.accentColor : .primary)
                                    .lineLimit(1)
                                Spacer()
                                if idx == chapterIndex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .onAppear {
                            Task { await ensurePageLoaded(for: idx) }
                        }
                        Divider()
                    }
                }
            }
            .navigationTitle("章节")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showChapterSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func chapterTitle(_ index: Int) -> String {
        chaptersByIndex[index]?.title ?? "第\(index + 1)章"
    }

    // MARK: - 数据加载

    private func bootstrap() async {
        await ensurePageLoaded(for: chapterIndex)
        guard totalChapters > 0 else {
            loadErrorMessage = "无法加载章节目录"
            return
        }
        // 越界保护（进度里的章序可能超出当前目录）
        if chapterIndex >= totalChapters { chapterIndex = totalChapters - 1 }
        await loadContent()
    }

    private func loadContent() async {
        isLoadingContent = true
        loadErrorMessage = nil
        defer { isLoadingContent = false }
        do {
            let text = try await EbookService.shared.fetchChapterContent(
                id: book.id, chapterIndex: chapterIndex
            )
            chapterText = text
            scrollFraction = 0
            report()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func goToChapter(_ index: Int) async {
        guard index >= 0, index != chapterIndex,
              totalChapters <= 0 || index < totalChapters else { return }
        chapterIndex = index
        await ensurePageLoaded(for: index)
        await loadContent()
    }

    /// 按需拉取包含目标章的那一页目录（同页并发去重）
    private func ensurePageLoaded(for chapterIdx: Int) async {
        let page = chapterIdx / pageSize
        guard !loadedPages.contains(page), !loadingPages.contains(page) else { return }
        loadingPages.insert(page)
        defer { loadingPages.remove(page) }
        do {
            let result = try await EbookService.shared.fetchChapterPage(id: book.id, page: page, size: pageSize)
            for chapter in result.content ?? [] {
                chaptersByIndex[chapter.index] = chapter
            }
            loadedPages.insert(page)
            if totalChapters <= 0, let total = result.totalElements, total > 0 {
                totalChapters = Int(total)
            }
        } catch {
            // 目录页失败不阻塞正文阅读；再次 onAppear 会重试
        }
    }

    // MARK: - 进度

    /// 整书百分比 = (全局章序 + 章内滚动比例) / 总章数
    private func report() {
        guard totalChapters > 0 else { return }
        let percent = (Double(chapterIndex) + scrollFraction) / Double(totalChapters) * 100
        onProgress(min(100, percent), chapterIndex)
    }
}

// MARK: - 滚动高度测量

/// 正文内容总高（含 padding）
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 滚动视口高
private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 正文内容顶部在滚动坐标系中的偏移（向下滚动为负）
private struct ContentTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

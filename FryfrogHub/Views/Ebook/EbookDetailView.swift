import SwiftUI

/// 电子书详情页
struct EbookDetailView: View {
    let bookId: Int64
    // 独立实例：共用单例时 selectedBook 残留上一本书（同 ComicDetailView）
    @State private var service = EbookService()
    @State private var showingMarkCompleted = false
    @State private var showingUnbind = false
    @State private var showingScrape = false
    @State private var showingReader = false

    private var book: EbookDetailDTO? { service.selectedBook }

    var body: some View {
        Group {
            if service.isLoading && book == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let book = book {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(book: book)

                        if let overview = book.overview, !overview.isEmpty {
                            overviewSection(overview)
                        }

                        if let progress = book.progress {
                            progressSection(progress)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .navigationTitle(book.title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if book.readable {
                        Button {
                            showingReader = true
                        } label: {
                            Label(
                                book.progress?.positionPercent ?? 0 > 0 ? "继续阅读" : "开始阅读",
                                systemImage: "book"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    } else {
                        Text("该格式暂不支持应用内阅读，可通过下载打开")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
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
            await service.loadBookDetail(id: bookId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let book = book {
                        Button {
                            showingMarkCompleted = true
                        } label: {
                            Label(
                                book.progress?.completed == true ? "标记为未读完" : "标记为已读完",
                                systemImage: book.progress?.completed == true ? "xmark.circle" : "checkmark.circle"
                            )
                        }

                        if book.progress != nil {
                            Button(role: .destructive) {
                                Task {
                                    try? await service.deleteProgress(id: bookId)
                                    await service.loadBookDetail(id: bookId)
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
                           book.metadataSource == "scrape" {
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
            EbookScrapeView(bookId: bookId, initialQuery: book?.title ?? "") {
                Task { await service.loadBookDetail(id: bookId) }
            }
        }
        .fullScreenCover(isPresented: $showingReader) {
            if let book = book, let fileURL = book.fileURL {
                EbookReaderView(book: book, fileURL: fileURL)
            }
        }
        .alert("解绑刮削元数据", isPresented: $showingUnbind) {
            Button("取消", role: .cancel) {}
            Button("解绑", role: .destructive) {
                Task {
                    try? await service.unbind(id: bookId)
                    await service.loadBookDetail(id: bookId)
                }
            }
        } message: {
            Text("将清除刮削绑定标记，已写入的书名、作者、简介等字段会保留。")
        }
        .alert("标记读完", isPresented: $showingMarkCompleted) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                Task {
                    let completed = book?.progress?.completed != true
                    try? await service.setCompleted(id: bookId, completed: completed)
                    await service.loadBookDetail(id: bookId)
                }
            }
        } message: {
            if let book = book {
                if book.progress?.completed == true {
                    Text("确定要将「\(book.title)」标记为未读完吗？")
                } else {
                    Text("确定要将「\(book.title)」标记为已读完吗？")
                }
            }
        }
    }

    // MARK: - 头部

    @ViewBuilder
    private func headerSection(book: EbookDetailDTO) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: book.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "text.book.closed")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title3.weight(.semibold))

                if let author = book.author {
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let publisher = book.publisher {
                    Label(publisher, systemImage: "building.columns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(book.formatText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)

                    if let pubYear = book.pubYear {
                        Label(String(pubYear), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let fileSize = book.fileSizeText {
                        Label(fileSize, systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let series = book.series {
                    Label(book.seriesPart.map { "\(series) #\($0)" } ?? series,
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
    private func progressSection(_ progress: EbookDetailDTO.ProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("阅读进度")
                    .font(.headline)
                Spacer()
                if let percent = progress.positionPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = progress.positionPercent {
                ProgressView(value: percent, total: 100)
                    .tint(progress.completed == true ? .green : .blue)
            }
        }
    }
}

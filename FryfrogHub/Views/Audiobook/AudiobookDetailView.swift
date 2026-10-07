import SwiftUI

/// 有声书详情页
struct AudiobookDetailView: View {
    let bookId: Int64
    @State private var service = AudiobookService.shared
    @State private var player = AudiobookPlayerService.shared
    @State private var showingMarkCompleted = false
    @State private var showingUnbind = false
    @State private var showingScrape = false

    private var book: AudiobookDetailDTO? { service.selectedBook }

    var body: some View {
        Group {
            if service.isLoading && book == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let book = book {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 头部：封面 + 信息
                            headerSection(book: book)

                            // 进度信息
                            if let progress = book.progress {
                                progressSection(progress: progress)
                            }

                            // 章节/音轨列表
                            if let chapters = book.chapters, !chapters.isEmpty {
                                chaptersSection(chapters: chapters, book: book)
                            } else if let tracks = book.tracks, !tracks.isEmpty {
                                tracksSection(tracks: tracks)
                            }
                        }
                        .padding()
                    }
                    .scrollIndicators(.hidden)

                    // 底部迷你播放器
                    AudiobookMiniPlayer()
                }
                .navigationTitle(book.title)
                .navigationBarTitleDisplayMode(.inline)
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
                                book.progress?.completed == true ? "标记为未听完" : "标记为已听完",
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
            AudiobookScrapeView(bookId: bookId, initialQuery: book?.title ?? "") {
                Task { await service.loadBookDetail(id: bookId) }
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
        .alert("标记听完", isPresented: $showingMarkCompleted) {
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
                    Text("确定要将「\(book.title)」标记为未听完吗？")
                } else {
                    Text("确定要将「\(book.title)」标记为已听完吗？")
                }
            }
        }
    }

    // MARK: - 头部

    @ViewBuilder
    private func headerSection(book: AudiobookDetailDTO) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // 封面
            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            // 信息
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title2.bold())

                if let author = book.author {
                    LabeledContent("作者", value: author)
                        .font(.subheadline)
                }

                if let narrator = book.narrator {
                    LabeledContent("朗读", value: narrator)
                        .font(.subheadline)
                }

                if let series = book.series {
                    LabeledContent("丛书", value: series)
                        .font(.subheadline)
                }

                LabeledContent("时长", value: book.durationText)
                    .font(.subheadline)

                if let trackCount = book.trackCount {
                    LabeledContent("音轨", value: "\(trackCount)个")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 进度

    @ViewBuilder
    private func progressSection(progress: AudiobookDetailDTO.ProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("收听进度")
                    .font(.headline)
                Spacer()
                if let percent = progress.percent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if progress.completed == true {
                    Text("已听完")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            if let percent = progress.percent {
                ProgressView(value: percent, total: 100)
                    .tint(progress.completed == true ? .green : .blue)
            }

            if let trackIndex = progress.trackIndex {
                Text("当前：第 \(trackIndex + 1) 轨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 章节列表

    @ViewBuilder
    private func chaptersSection(chapters: [AudiobookChapterDTO], book: AudiobookDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("章节目录")
                    .font(.headline)

                Spacer()

                // 继续播放按钮
                if let progress = book.progress,
                   let trackIndex = progress.trackIndex,
                   let tracks = book.tracks,
                   trackIndex < tracks.count {
                    Button {
                        player.restorePosition(for: book)
                    } label: {
                        Label("继续播放", systemImage: "play.fill")
                            .font(.subheadline)
                    }
                }
            }

            ForEach(chapters) { chapter in
                Button {
                    player.playChapter(book: book, chapter: chapter)
                } label: {
                    HStack {
                        // 章节序号
                        Text("\(chapter.chapterIndex ?? 0 + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title ?? "第 \(chapter.chapterIndex ?? 0) 章")
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(.primary)

                            Text(chapter.durationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // 当前播放标记
                        if let progress = book.progress,
                           let chapterIndex = chapter.chapterIndex,
                           progress.trackIndex == chapter.trackIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if chapter.id != chapters.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - 音轨列表

    @ViewBuilder
    private func tracksSection(tracks: [AudiobookTrackDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("音轨列表")
                    .font(.headline)

                Spacer()

                // 继续播放按钮
                if let book = book,
                   let progress = book.progress,
                   let trackIndex = progress.trackIndex,
                   trackIndex < tracks.count {
                    Button {
                        player.restorePosition(for: book)
                    } label: {
                        Label("继续播放", systemImage: "play.fill")
                            .font(.subheadline)
                    }
                }
            }

            ForEach(tracks) { track in
                Button {
                    if let book = book {
                        player.play(book: book, track: track)
                    }
                } label: {
                    HStack {
                        // 轨序号
                        Text("\(track.trackIndex ?? 0 + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title ?? "第 \(track.trackIndex ?? 0) 轨")
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(.primary)

                            HStack(spacing: 8) {
                                Text(track.durationText)
                                if !track.fileSizeText.isEmpty {
                                    Text(track.fileSizeText)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // 当前播放标记
                        if let book = book,
                           let progress = book.progress,
                           progress.trackIndex == track.trackIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if track.id != tracks.last?.id {
                    Divider()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AudiobookDetailView(bookId: 1)
    }
}

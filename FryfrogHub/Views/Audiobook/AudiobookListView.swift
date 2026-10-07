import SwiftUI

/// 有声书列表（书架 Tab 内嵌，无独立 NavigationStack）
struct AudiobookLibraryView: View {
    @State private var service = AudiobookService.shared
    @State private var searchText = ""

    var body: some View {
        Group {
            if service.isLoading && service.books.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.books.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "未找到有声书",
                    systemImage: "book.closed",
                    description: Text("没有匹配「\(searchText)」的有声书")
                )
            } else if service.books.isEmpty {
                ContentUnavailableView(
                    "暂无有声书",
                    systemImage: "book.closed",
                    description: Text("在「资源库」中扫描有声书目录")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(service.books) { book in
                            NavigationLink {
                                AudiobookDetailView(bookId: book.id)
                            } label: {
                                AudiobookRow(book: book)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if book.id == service.books.last?.id {
                                    Task { await service.loadMoreBooks() }
                                }
                            }
                        }

                        if service.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: "搜索有声书")
        .onSubmit(of: .search) {
            Task { await service.loadBooks(query: searchText) }
        }
        .task {
            if service.books.isEmpty {
                await service.loadBooks()
            }
        }
        .refreshable {
            await service.loadBooks(query: searchText)
        }
    }
}

/// 有声书列表行
private struct AudiobookRow: View {
    let book: AudiobookListDTO

    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "book.closed")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                    }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)

                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let narrator = book.narrator {
                    Text("朗读：\(narrator)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let durationText = book.durationText as String? {
                        Label(durationText, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let trackCount = book.trackCount {
                        Label("\(trackCount)集", systemImage: "list.number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 进度条
                if let percent = book.progressPercent {
                    ProgressView(value: percent, total: 100)
                        .tint(book.completed == true ? .green : .blue)
                        .frame(height: 4)
                }
            }

            Spacer()

            // 完成标记
            if book.completed == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AudiobookLibraryView()
            .navigationTitle("有声书")
    }
}

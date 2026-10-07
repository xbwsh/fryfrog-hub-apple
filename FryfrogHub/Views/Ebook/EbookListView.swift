import SwiftUI

/// 电子书列表（书架 Tab 内嵌，无独立 NavigationStack）
struct EbookLibraryView: View {
    @State private var service = EbookService.shared
    @State private var searchText = ""

    var body: some View {
        Group {
                if service.isLoading && service.books.isEmpty {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.books.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "未找到电子书",
                        systemImage: "text.book.closed",
                        description: Text("没有匹配「\(searchText)」的电子书")
                    )
                } else if service.books.isEmpty {
                    ContentUnavailableView(
                        "暂无电子书",
                        systemImage: "text.book.closed",
                        description: Text("在「资源库」中扫描电子书目录")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(service.books) { book in
                                NavigationLink {
                                    EbookDetailView(bookId: book.id)
                                } label: {
                                    EbookRow(book: book)
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
            .searchable(text: $searchText, prompt: "搜索电子书")
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

/// 电子书列表行
private struct EbookRow: View {
    let book: EbookListDTO

    var body: some View {
        HStack(spacing: 12) {
            // 封面（书籍比例）
            AsyncImage(url: book.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "text.book.closed")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 56, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let series = book.series {
                    Text(series)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let format = book.format {
                        Text(format)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.15), in: Capsule())
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
        EbookLibraryView()
            .navigationTitle("电子书")
    }
}

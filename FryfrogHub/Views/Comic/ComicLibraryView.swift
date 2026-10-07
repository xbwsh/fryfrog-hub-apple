import SwiftUI

/// 漫画列表（书架 Tab 内嵌，无独立 NavigationStack）
struct ComicLibraryView: View {
    @State private var service = ComicService.shared
    @State private var searchText = ""

    var body: some View {
        Group {
            if service.isLoading && service.comics.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.comics.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "未找到漫画",
                    systemImage: "book",
                    description: Text("没有匹配「\(searchText)」的漫画")
                )
            } else if service.comics.isEmpty {
                ContentUnavailableView(
                    "暂无漫画",
                    systemImage: "book",
                    description: Text("在「资源库」中扫描漫画目录")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 20) {
                        ForEach(service.comics) { comic in
                            NavigationLink {
                                ComicDetailView(comicId: comic.id)
                            } label: {
                                ComicCoverCell(comic: comic)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if comic.id == service.comics.last?.id {
                                    Task { await service.loadMoreComics() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: "搜索漫画")
        .onSubmit(of: .search) {
            Task { await service.loadComics(query: searchText) }
        }
        .task {
            if service.comics.isEmpty {
                await service.loadComics()
            }
        }
        .refreshable {
            await service.loadComics(query: searchText)
        }
    }
}

/// 封面网格单元
private struct ComicCoverCell: View {
    let comic: ComicListDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: comic.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(2.0/2.9, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "book")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 110, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(comic.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let percent = comic.progressPercent {
                ProgressView(value: percent, total: 100)
                    .tint(comic.completed == true ? .green : .blue)
                    .frame(height: 3)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ComicLibraryView()
    }
}

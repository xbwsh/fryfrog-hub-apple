import SwiftUI

/// 我的收藏：收藏的电影与剧集海报网格（分两段展示）
struct FavoritesView: View {
    @State private var movies: [SeriesListDTO] = []
    @State private var series: [SeriesListDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var privacy: PrivacySettings { .shared }
    private var client: APIClient { .shared }

    private var isEmpty: Bool { movies.isEmpty && series.isEmpty }

    var body: some View {
        Group {
            if isLoading && isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "heart",
                    description: Text(errorMessage ?? "在视频详情页右上角菜单里点击收藏")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !movies.isEmpty {
                            favoriteSection(title: "电影", items: movies)
                        }
                        if !series.isEmpty {
                            favoriteSection(title: "剧集", items: series)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private func favoriteSection(title: String, items: [SeriesListDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 20) {
                ForEach(items) { item in
                    NavigationLink {
                        SeriesDetailView(series: item) { _ in
                            Task { await load() }
                        }
                    } label: {
                        PosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 并行拉取剧集收藏与电影收藏
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let seriesResponse: ApiResponse<[SeriesListDTO]> = client.request("/api/v1/video/series/favorites")
            async let movieResponse: ApiResponse<PageResponseVideoDTO> = client.request(
                "/api/v1/video/favorites",
                queryItems: [
                    URLQueryItem(name: "page", value: "0"),
                    URLQueryItem(name: "size", value: "100")
                ]
            )
            let (seriesData, movieData) = try await (seriesResponse, movieResponse)

            var allSeries = seriesData.data ?? []
            var allMovies = (movieData.data?.content ?? []).map { $0.seriesListDTO }
            if privacy.isEnabled {
                allSeries = allSeries.filter { $0.isAdult != true }
                allMovies = allMovies.filter { $0.isAdult != true }
            }
            series = allSeries
            movies = allMovies
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
    }
}

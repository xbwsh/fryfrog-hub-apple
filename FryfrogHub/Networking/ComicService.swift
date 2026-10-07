import Foundation
import Observation

/// 漫画数据服务：列表、详情、阅读进度、刮削。
@MainActor
@Observable
final class ComicService {
    static let shared = ComicService()

    private let client: any APIClientProtocol

    private(set) var comics: [ComicListDTO] = []
    private(set) var selectedComic: ComicDetailDTO?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var currentPage = 0
    private(set) var hasMore = true
    private(set) var searchQuery = ""
    var errorMessage: String?

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    // MARK: - 列表

    func loadComics(query: String = "") async {
        searchQuery = query
        comics = []
        currentPage = 0
        hasMore = true
        await loadComicsPage(page: 0, query: query, append: false)
    }

    func loadMoreComics() async {
        guard hasMore, !isLoadingMore else { return }
        await loadComicsPage(page: currentPage + 1, query: searchQuery, append: true)
    }

    private func loadComicsPage(page: Int, query: String, append: Bool) async {
        if append {
            isLoadingMore = true
        } else {
            isLoading = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            var queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: "20")
            ]
            if !query.isEmpty {
                queryItems.append(URLQueryItem(name: "q", value: query))
            }
            let response: ApiResponse<PageResponse<ComicListDTO>> = try await client.request(
                "/api/v1/comics",
                queryItems: queryItems
            )
            let pageData = response.data
            let newComics = pageData?.content ?? []
            if append {
                comics.append(contentsOf: newComics)
            } else {
                comics = newComics
            }
            currentPage = page
            hasMore = newComics.count >= 20 && (pageData?.totalElements.map { comics.count < $0 } ?? false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 详情

    func loadComicDetail(id: Int64) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: ApiResponse<ComicDetailDTO> = try await client.request("/api/v1/comics/\(id)")
            selectedComic = response.data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 扫描

    func scan(libraryId: Int64? = nil) async throws {
        guard AuthService.shared.currentUser?.isAdmin == true else {
            throw APIError.httpError(statusCode: 403, message: "无操作权限")
        }
        var queryItems: [URLQueryItem] = []
        if let libraryId = libraryId {
            queryItems.append(URLQueryItem(name: "libraryId", value: String(libraryId)))
        }
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/comics/scan",
            method: "POST",
            queryItems: queryItems
        )
    }

    // MARK: - 阅读进度

    func updateProgress(id: Int64, chapterIndex: Int, pageIndex: Int) async throws {
        let body = AnyEncodable(["chapterIndex": chapterIndex, "pageIndex": pageIndex])
        let _: ApiResponse<ComicDetailDTO.ProgressDTO> = try await client.request(
            "/api/v1/comics/\(id)/progress",
            method: "PUT",
            body: body
        )
    }

    func setCompleted(id: Int64, completed: Bool) async throws {
        let body = AnyEncodable(["completed": completed])
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/comics/\(id)/completed",
            method: "PUT",
            body: body
        )
    }

    func deleteProgress(id: Int64) async throws {
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/comics/\(id)/progress",
            method: "DELETE"
        )
    }

    // MARK: - 刮削

    /// 搜索刮削候选（Bangumi）
    func searchScrape(_ keyword: String) async throws -> [ComicScrapeCandidate] {
        let response: ApiResponse<[ComicScrapeCandidate]> = try await client.request(
            "/api/v1/comics/scrape/search",
            queryItems: [URLQueryItem(name: "q", value: keyword)]
        )
        return response.data ?? []
    }

    /// 绑定刮削元数据（结果落库并下载封面）
    func bindScrape(id: Int64, source: String, sourceId: String) async throws {
        let body = AnyEncodable(["source": source, "sourceId": sourceId])
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/comics/\(id)/scrape/bind",
            method: "POST",
            body: body
        )
    }

    /// 解绑刮削元数据（已写入的字段保留）
    func unbind(id: Int64) async throws {
        guard AuthService.shared.currentUser?.isAdmin == true else {
            throw APIError.httpError(statusCode: 403, message: "无操作权限")
        }
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/comics/\(id)/scrape/unbind",
            method: "POST"
        )
    }

    // MARK: - 重载

    func reload() async {
        selectedComic = nil
        await loadComics(query: searchQuery)
    }
}

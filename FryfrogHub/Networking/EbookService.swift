import Foundation
import Observation

/// 电子书数据服务：列表、详情、阅读进度、刮削。
@MainActor
@Observable
final class EbookService {
    static let shared = EbookService()

    private let client: any APIClientProtocol
    private let server: any ServerConnectionProtocol

    private(set) var books: [EbookListDTO] = []
    private(set) var selectedBook: EbookDetailDTO?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var currentPage = 0
    private(set) var hasMore = true
    private(set) var searchQuery = ""
    var errorMessage: String?

    init(client: any APIClientProtocol = APIClient.shared, server: any ServerConnectionProtocol = ServerConnection.shared) {
        self.client = client
        self.server = server
    }

    // MARK: - 列表

    func loadBooks(query: String = "") async {
        searchQuery = query
        books = []
        currentPage = 0
        hasMore = true
        await loadBooksPage(page: 0, query: query, append: false)
    }

    func loadMoreBooks() async {
        guard hasMore, !isLoadingMore else { return }
        await loadBooksPage(page: currentPage + 1, query: searchQuery, append: true)
    }

    private func loadBooksPage(page: Int, query: String, append: Bool) async {
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
            let response: ApiResponse<PageResponse<EbookListDTO>> = try await client.request(
                "/api/v1/ebooks",
                queryItems: queryItems
            )
            let pageData = response.data
            let newBooks = pageData?.content ?? []
            if append {
                books.append(contentsOf: newBooks)
            } else {
                books = newBooks
            }
            currentPage = page
            hasMore = newBooks.count >= 20 && (pageData?.totalElements.map { books.count < $0 } ?? false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 详情

    func loadBookDetail(id: Int64) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: ApiResponse<EbookDetailDTO> = try await client.request("/api/v1/ebooks/\(id)")
            selectedBook = response.data
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
            "/api/v1/ebooks/scan",
            method: "POST",
            queryItems: queryItems
        )
    }

    // MARK: - 阅读进度

    func updateProgress(id: Int64, positionPercent: Double, chapterIndex: Int?) async throws {
        let body = AnyEncodable(EbookProgressRequest(positionPercent: positionPercent, chapterIndex: chapterIndex))
        let _: ApiResponse<EbookDetailDTO.ProgressDTO> = try await client.request(
            "/api/v1/ebooks/\(id)/progress",
            method: "PUT",
            body: body
        )
    }

    func setCompleted(id: Int64, completed: Bool) async throws {
        let body = AnyEncodable(EbookCompletedRequest(completed: completed))
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/ebooks/\(id)/completed",
            method: "PUT",
            body: body
        )
    }

    func deleteProgress(id: Int64) async throws {
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/ebooks/\(id)/progress",
            method: "DELETE"
        )
    }

    // MARK: - 刮削

    /// 搜索刮削候选（Bangumi）
    func searchScrape(_ keyword: String) async throws -> [EbookScrapeCandidate] {
        let response: ApiResponse<[EbookScrapeCandidate]> = try await client.request(
            "/api/v1/ebooks/scrape/search",
            queryItems: [URLQueryItem(name: "q", value: keyword)]
        )
        return response.data ?? []
    }

    /// 绑定刮削元数据（结果落库并下载封面）
    func bindScrape(id: Int64, source: String, sourceId: String) async throws {
        let body = AnyEncodable(["source": source, "sourceId": sourceId])
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/ebooks/\(id)/scrape/bind",
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
            "/api/v1/ebooks/\(id)/scrape/unbind",
            method: "POST"
        )
    }

    // MARK: - 重载

    func reload() async {
        selectedBook = nil
        await loadBooks(query: searchQuery)
    }
}

// MARK: - 请求体

struct EbookProgressRequest: Encodable {
    let positionPercent: Double
    let chapterIndex: Int?
}

struct EbookCompletedRequest: Encodable {
    let completed: Bool
}

import Foundation
import Observation

@Observable
final class MediaLibraryService {
    static let shared = MediaLibraryService()

    private let client: any APIClientProtocol
    /// 预留：与其它 Service 统一注入契约（当前方法未直接使用）
    private let server: any ServerConnectionProtocol

    private(set) var libraries: [MediaLibrary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// T3-1：默认单例入口；测试可注入协议替身
    init(client: any APIClientProtocol = APIClient.shared, server: any ServerConnectionProtocol = ServerConnection.shared) {
        self.client = client
        self.server = server
    }

    /// 拉取所有资源库
    func fetchLibraries() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: ApiResponse<[MediaLibrary]> = try await client.request("/api/v1/media-libraries")
            libraries = response.data ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 管理（增删改 / 启停 / 扫描）

extension MediaLibraryService {
    /// 创建资源库
    func create(_ request: MediaLibraryRequest) async throws {
        let _: ApiResponse<MediaLibrary> = try await client.request(
            "/api/v1/media-libraries",
            method: "POST",
            body: AnyEncodable(request)
        )
    }

    /// 更新资源库（仅提交需要修改的字段）
    func update(_ id: Int64, request: MediaLibraryRequest) async throws {
        let _: ApiResponse<MediaLibrary> = try await client.request(
            "/api/v1/media-libraries/\(id)",
            method: "PUT",
            body: AnyEncodable(request)
        )
    }

    /// 删除资源库
    func delete(id: Int64) async throws {
        let _: ApiResponse<[String: String]> = try await client.request(
            "/api/v1/media-libraries/\(id)",
            method: "DELETE"
        )
    }

    /// 启用/停用资源库
    func toggle(id: Int64) async throws {
        let _: ApiResponse<MediaLibrary> = try await client.request(
            "/api/v1/media-libraries/\(id)/toggle",
            method: "PUT"
        )
    }

    /// 扫描指定资源库（异步执行，进度通过 pipeline-progress 轮询）
    func scan(id: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/media-libraries/\(id)/scan",
            method: "POST"
        )
    }

    /// 扫描全部启用中的资源库
    func scanAll() async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/media-libraries/scan",
            method: "POST"
        )
    }

    /// 指定资源库的流水线进度（nil = 拉取失败）
    func pipelineProgress(id: Int64) async -> PipelineProgressDTO? {
        let response: ApiResponse<PipelineProgressDTO>? = try? await client.request(
            "/api/v1/media-libraries/\(id)/pipeline-progress"
        )
        return response?.data
    }

    /// 浏览服务器目录（path 为空时返回磁盘根目录）
    func browse(path: String?) async -> [LibraryBrowseItem] {
        var queryItems: [URLQueryItem] = []
        if let path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        let response: ApiResponse<[LibraryBrowseItem]>? = try? await client.request(
            "/api/v1/media-libraries/browse",
            queryItems: queryItems
        )
        return response?.data ?? []
    }
}

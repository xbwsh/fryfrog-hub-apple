import Foundation
import Observation

/// 外挂字幕文件（来自 GET /api/v1/video/{id}/subtitles）
struct SubtitleFile: Codable, Identifiable {
    let filename: String
    let language: String?
    let url: String?

    var id: String { url ?? filename }
}

/// 视频详情页数据服务：详情、演员、观看进度
/// 与 MusicService 等一致整体标注 @MainActor：detail/movie/actors 仅主线程变更
/// （此前 load/loadActors 的 defer/catch 在通用执行器写，与主线程渲染竞态）
@MainActor
@Observable
final class VideoService {
    static let shared = VideoService()

    private let client: any APIClientProtocol
    private let server: any ServerConnectionProtocol

    private(set) var isLoading = false
    private(set) var detail: SeriesDTO?
    private(set) var movie: VideoDTO?
    private(set) var actors: [VideoActor] = []
    var errorMessage: String?

    /// T3-1：默认单例入口；测试可注入协议替身
    init(client: any APIClientProtocol = APIClient.shared, server: any ServerConnectionProtocol = ServerConnection.shared) {
        self.client = client
        self.server = server
    }

    /// 清空上次数据（详情页每次进入重新拉取）
    func reset() {
        detail = nil
        movie = nil
        actors = []
        errorMessage = nil
    }

    /// 拉取详情：独立视频用视频接口，系列用系列接口
    func load(id: Int64, isStandalone: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isStandalone {
                let response: ApiResponse<VideoDTO> = try await client.request("/api/v1/video/\(id)")
                movie = response.data
            } else {
                let response: ApiResponse<SeriesDTO> = try await client.request("/api/v1/video/series/\(id)")
                detail = response.data
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 拉取演员列表（非关键信息，失败静默）
    func loadActors(id: Int64) async {
        do {
            let response: ApiResponse<[VideoActor]> = try await client.request("/api/v1/video/\(id)/actors")
            actors = response.data ?? []
        } catch {
            actors = []
        }
    }

    /// 拉取系列演员列表（电视剧，GET /api/v1/video/series/{id}/actors，去重）
    func loadSeriesActors(seriesId: Int64) async {
        do {
            let response: ApiResponse<[VideoActor]> = try await client.request("/api/v1/video/series/\(seriesId)/actors")
            actors = response.data ?? []
        } catch {
            actors = []
        }
    }

    /// 拉取演员详情（GET /api/v1/video/actor/{actorId}）
    /// 数据来自落库缓存：首次访问可能需等待 TMDB 拉取（几秒内），之后 7 天内秒回。
    /// 演员不存在或所在媒体库不可见 → 404（抛 APIError.httpError）。
    func fetchActorDetail(actorId: Int64) async throws -> ActorDetailDTO {
        let response: ApiResponse<ActorDetailDTO> = try await client.request("/api/v1/video/actor/\(actorId)")
        guard let data = response.data else {
            throw APIError.httpError(statusCode: 404, message: "演员不存在")
        }
        return data
    }

    /// 强制刷新演员详情缓存（管理员，GET /api/v1/video/actor/{actorId}/refresh）
    func refreshActor(actorId: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/actor/\(actorId)/refresh",
            method: "POST"
        )
    }

    /// 拉取演员作品列表（GET /api/v1/video/actor/{actorId}/works，按系列聚合分页）
    /// 返回 PageResponse<SeriesListDTO>：同一剧集所有命中的集折叠为一部（type="series"，id 为系列 ID，
    /// 封面为系列封面），独立视频/电影各自为一部（type="standalone"，id 为视频 ID），按年份降序。
    /// 演员存在但无作品 → 200 空 content；演员不存在 → 404（抛 APIError.httpError）。
    /// 注意前端以 HTTP 状态码区分，不能只看 success。
    func fetchActorWorks(actorId: Int64, page: Int = 0, size: Int = 20) async throws -> PageResponse<SeriesListDTO> {
        let response: ApiResponse<PageResponse<SeriesListDTO>> = try await client.request(
            "/api/v1/video/actor/\(actorId)/works",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size))
            ]
        )
        return response.data ?? PageResponse(content: [], page: page, size: size, totalElements: 0, totalPages: 0)
    }

    /// 获取观看进度（用于续播）
    func fetchProgress(id: Int64) async -> WatchProgressDTO? {
        do {
            let response: ApiResponse<WatchProgressDTO> = try await client.request("/api/v1/video/\(id)/progress")
            return response.data
        } catch {
            return nil
        }
    }

    /// 更新播放位置（退出播放器时调用，服务端自动判定是否看完）
    func updatePosition(id: Int64, position: Double, duration: Double) async {
        guard position.isFinite, position > 0 else { return }
        let body = UpdatePositionRequest(position: position, duration: duration.isFinite ? duration : 0)
        do {
            _ = try await client.request(
                "/api/v1/video/\(id)/progress",
                method: "PUT",
                body: AnyEncodable(body)
            ) as ApiResponse<WatchProgressDTO>?
        } catch {
            AppLog.networking.warning("上报播放位置失败 id=\(id): \(AppLog.describe(error))")
        }
    }

    /// 设置已看完状态
    func setWatched(id: Int64, completed: Bool) async {
        let body = UpdateWatchedRequest(completed: completed)
        do {
            _ = try await client.request(
                "/api/v1/video/\(id)/watched",
                method: "PUT",
                body: AnyEncodable(body)
            ) as ApiResponse<WatchProgressDTO>?
        } catch {
            AppLog.networking.warning("设置已看完失败 id=\(id): \(AppLog.describe(error))")
        }
    }

    /// 原画流播放地址（直连，不做转码）
    func streamURL(id: Int64) -> URL {
        URL(string: server.activeURLString + "/api/v1/video/\(id)/stream")!
    }

    /// 拉取视频详情中的新鲜签名流地址（播放前刷新，签名 7 天过期且与密钥绑定）
    /// T3-1：供播放器视图经 Service 访问，避免视图层硬编码 APIClient.shared
    func freshStreamPath(id: Int64) async throws -> String? {
        let response: ApiResponse<VideoDTO> = try await client.request("/api/v1/video/\(id)")
        return response.data?.streamUrl
    }

    /// 当前会话 token（播放器为 mpv/AVPlayer 请求头读取）
    /// T3-1：同上，收敛视图层对客户端单例的直接依赖
    func authToken() async -> String? {
        await client.currentToken
    }

    /// 拉取外挂字幕列表（url 为后端返回的签名地址，禁止改写，直接拼接/透传）
    func fetchSubtitles(id: Int64) async -> [SubtitleFile] {
        do {
            let response: ApiResponse<[SubtitleFile]> = try await client.request("/api/v1/video/\(id)/subtitles")
            return (response.data ?? []).map { file in
                SubtitleFile(
                    filename: file.filename,
                    language: file.language,
                    url: file.url.flatMap { server.imageURL(for: $0)?.absoluteString }
                )
            }
        } catch {
            AppLog.networking.warning("外挂字幕列表拉取失败 videoId=\(id): \(AppLog.describe(error))")
            return []
        }
    }

    // MARK: - 维护（TMDB / 元数据 / Logo）

    /// 搜索 TMDB（电影/电视剧）
    func searchTmdb(_ query: String) async throws -> [TmdbSearchItem] {
        let response: ApiResponse<[TmdbSearchItem]> = try await client.request(
            "/api/v1/video/tmdb/search",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
        return response.data ?? []
    }

    /// 绑定 TMDB（videoId 为系列时绑定整个同标题系列）
    func bindTmdb(videoId: Int64, tmdbId: Int64, mediaType: String) async throws {
        let body = VideoBindRequest(tmdbId: tmdbId, mediaType: mediaType)
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(videoId)/tmdb/bind",
            method: "POST",
            body: AnyEncodable(body)
        )
    }

    /// 解绑 TMDB
    func unbindTmdb(videoId: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(videoId)/tmdb/unbind",
            method: "POST"
        )
    }

    /// 刷新 TMDB 元数据（重新搜索绑定 + 重命名文件，异步）
    func refreshTmdb(videoId: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(videoId)/tmdb/refresh",
            method: "POST"
        )
    }

    /// 编辑视频元数据（只更新非空字段）
    func updateVideoMetadata(id: Int64, request: VideoMetadataUpdateRequest) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(id)/metadata",
            method: "PUT",
            body: AnyEncodable(request)
        )
    }

    /// 编辑系列元数据（只更新非空字段）
    func updateSeriesMetadata(id: Int64, request: SeriesMetadataUpdateRequest) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/series/\(id)/metadata",
            method: "PUT",
            body: AnyEncodable(request)
        )
    }

    /// 补全电影 Logo
    func refreshMovieLogo(id: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(id)/refresh-logo",
            method: "POST"
        )
    }

    /// 补全系列 Logo
    func refreshSeriesLogo(id: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/series/\(id)/refresh-logo",
            method: "POST"
        )
    }

    /// 查询 Logo 选项（电影）
    func fetchMovieLogoOptions(id: Int64) async -> [LogoOption] {
        do {
            let response: ApiResponse<[LogoOption]> = try await client.request("/api/v1/video/\(id)/logo-options")
            return response.data ?? []
        } catch {
            AppLog.networking.warning("拉取电影 Logo 选项失败 id=\(id): \(AppLog.describe(error))")
            return []
        }
    }

    /// 查询 Logo 选项（系列）
    func fetchSeriesLogoOptions(id: Int64) async -> [LogoOption] {
        do {
            let response: ApiResponse<[LogoOption]> = try await client.request("/api/v1/video/series/\(id)/logo-options")
            return response.data ?? []
        } catch {
            AppLog.networking.warning("拉取系列 Logo 选项失败 id=\(id): \(AppLog.describe(error))")
            return []
        }
    }

    /// 生成截帧候选列表（异步，生成后可用 /frames/{index} 预览）
    func generateFrames(videoId: Int64) async throws {
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(videoId)/frames",
            method: "POST"
        )
    }

    /// 选择截帧作为封面/背景图（电影）
    func selectFrame(videoId: Int64, index: Int, type: String) async throws {
        let body = FrameSelectRequest(index: index, type: type)
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(videoId)/frames/select",
            method: "POST",
            body: AnyEncodable(body)
        )
    }

    /// 从单集截帧设置系列横屏背景图
    func selectSeriesFanart(seriesId: Int64, videoId: Int64, index: Int) async throws {
        let body = SeriesFrameSelectRequest(videoId: videoId, index: index)
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/series/\(seriesId)/frames/select",
            method: "POST",
            body: AnyEncodable(body)
        )
    }

    /// 设置电影 Logo（filePath 来自 logo-options）
    func setMovieLogo(id: Int64, filePath: String) async throws {
        let body = LogoSelectRequest(filePath: filePath)
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/\(id)/logo",
            method: "POST",
            body: AnyEncodable(body)
        )
    }

    /// 设置系列 Logo（filePath 来自 logo-options）
    func setSeriesLogo(id: Int64, filePath: String) async throws {
        let body = LogoSelectRequest(filePath: filePath)
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/video/series/\(id)/logo",
            method: "POST",
            body: AnyEncodable(body)
        )
    }
}

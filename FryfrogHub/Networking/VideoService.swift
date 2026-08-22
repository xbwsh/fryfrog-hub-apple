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
@Observable
final class VideoService {
    static let shared = VideoService()

    private let client = APIClient.shared

    private(set) var isLoading = false
    private(set) var detail: SeriesDTO?
    private(set) var movie: VideoDTO?
    private(set) var actors: [VideoActor] = []
    var errorMessage: String?

    private init() {}

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
        _ = try? await client.request(
            "/api/v1/video/\(id)/progress",
            method: "PUT",
            body: AnyEncodable(body)
        ) as ApiResponse<WatchProgressDTO>?
    }

    /// 设置已看完状态
    func setWatched(id: Int64, completed: Bool) async {
        let body = UpdateWatchedRequest(completed: completed)
        _ = try? await client.request(
            "/api/v1/video/\(id)/watched",
            method: "PUT",
            body: AnyEncodable(body)
        ) as ApiResponse<WatchProgressDTO>?
    }

    /// 原画流播放地址（直连，不做转码）
    func streamURL(id: Int64) -> URL {
        URL(string: ServerConnection.shared.activeURLString + "/api/v1/video/\(id)/stream")!
    }

    /// 拉取外挂字幕列表（url 为后端返回的签名地址，禁止改写，直接拼接/透传）
    func fetchSubtitles(id: Int64) async -> [SubtitleFile] {
        do {
            let response: ApiResponse<[SubtitleFile]> = try await client.request("/api/v1/video/\(id)/subtitles")
            return (response.data ?? []).map { file in
                SubtitleFile(
                    filename: file.filename,
                    language: file.language,
                    url: file.url.flatMap { ServerConnection.shared.imageURL(for: $0)?.absoluteString }
                )
            }
        } catch {
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
        (try? await client.request("/api/v1/video/\(id)/logo-options") as ApiResponse<[LogoOption]>?)?.data ?? []
    }

    /// 查询 Logo 选项（系列）
    func fetchSeriesLogoOptions(id: Int64) async -> [LogoOption] {
        (try? await client.request("/api/v1/video/series/\(id)/logo-options") as ApiResponse<[LogoOption]>?)?.data ?? []
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

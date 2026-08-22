import Foundation

/// 系列详情（GET /api/v1/video/series/{id}）
struct SeriesDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let type: String?
    let title: String?
    let coverUrl: String?
    let fanartUrl: String?
    let originalTitle: String?
    let overview: String?
    let logoUrl: String?
    let mediaType: String?
    let tmdbId: Int64?
    let rating: Double?
    let year: Int?
    let releaseDate: String?
    let seasonNumber: Int?
    let numberOfSeasons: Int?
    let totalEpisodes: Int?
    let status: String?
    let isAdult: Bool?
    let favorite: Bool?
    let episodeCount: Int?
    let seasons: [SeasonDTO]?
    let resolutions: [String]?

    var displayTitle: String { title ?? originalTitle ?? "(未命名)" }
    var isTV: Bool { mediaType?.lowercased() == "tv" }
    var yearText: String { year.map(String.init) ?? "" }
    var allEpisodes: [VideoDTO] { (seasons ?? []).flatMap { $0.episodes ?? [] } }
}

/// 季度信息，包含该季的所有剧集
struct SeasonDTO: Decodable, Identifiable, Hashable {
    let seasonNumber: Int?
    let coverUrl: String?
    let episodes: [VideoDTO]?

    var id: Int { seasonNumber ?? 0 }
    var seasonLabel: String {
        guard let n = seasonNumber, n > 0 else { return "特别篇" }
        return "第 \(n) 季"
    }
}

/// 视频详情（GET /api/v1/video/{id}，以及系列详情中的剧集条目）
struct VideoDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String?
    let coverUrl: String?
    let fanartUrl: String?
    let logoUrl: String?
    let streamUrl: String?
    let originalTitle: String?
    let director: String?
    let actors: String?
    let genre: String?
    let year: Int?
    let releaseDate: String?
    let durationMinutes: Int?
    let overview: String?
    let fileName: String?
    let originalFileName: String?
    let fileSize: Int64?
    let format: String?
    let resolution: String?
    let resolutionLabel: String?
    let favorite: Bool?
    let tmdbId: Int64?
    let mediaType: String?
    let imdbId: String?
    let rating: Double?
    let voteCount: Int?
    let status: String?
    let metadataSource: String?
    let metadataUpdatedAt: String?
    let hasMetadataDir: Bool?
    let hasNfo: Bool?
    let hasPoster: Bool?
    let hasFanart: Bool?
    let scraped: Bool?
    let isSeries: Bool?
    let libraryId: Int64?
    let seriesId: Int64?
    let seriesTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let watchPosition: Double?
    let watchProgressPercent: Double?
    let watched: Bool?
    let isAdult: Bool?

    var displayTitle: String { title ?? "(未命名)" }
    var yearText: String { year.map(String.init) ?? "" }

    /// 剧集编号，如 S01E05
    var episodeLabel: String {
        guard let season = seasonNumber, let episode = episodeNumber else { return "" }
        return String(format: "S%02dE%02d", season, episode)
    }

    var durationText: String {
        guard let minutes = durationMinutes, minutes > 0 else { return "" }
        return "\(minutes) 分钟"
    }

    /// 是否已看完
    var isWatched: Bool { watched == true }

    /// 转成轻量系列数据（type=standalone），用于收藏页海报卡片与详情跳转
    var seriesListDTO: SeriesListDTO {
        SeriesListDTO(
            id: id,
            type: "standalone",
            title: title,
            coverUrl: coverUrl,
            fanartUrl: fanartUrl,
            logoUrl: logoUrl,
            originalTitle: originalTitle,
            mediaType: mediaType,
            rating: rating,
            year: year,
            releaseDate: releaseDate,
            numberOfSeasons: nil,
            totalEpisodes: nil,
            episodeCount: nil,
            isAdult: isAdult,
            favorite: favorite,
            hasAdultEpisodes: nil,
            resolutions: resolutionLabel.map { [$0] }
        )
    }
}

/// 分页响应（GET /api/v1/video/favorites 等）
struct PageResponseVideoDTO: Decodable {
    let content: [VideoDTO]?
    let page: Int?
    let size: Int?
    let totalElements: Int64?
    let totalPages: Int?
}

/// 观看进度（GET/PUT /api/v1/video/{id}/progress）
struct WatchProgressDTO: Decodable, Hashable {
    let videoId: Int64?
    let positionSeconds: Double?
    let durationSeconds: Double?
    let completed: Bool?
    let progressPercent: Double?
    let updatedAt: String?
}

/// 演员信息（GET /api/v1/video/{id}/actors）
struct VideoActor: Decodable, Identifiable, Hashable {
    let id: Int64
    let createdAt: String?
    let updatedAt: String?
    let name: String?
    let character: String?
    let sourceActorId: Int64?
    let imageUrl: String?

    var displayName: String { name ?? "(未知演员)" }
    var characterText: String { character ?? "" }

    /// 头像地址：优先接口返回的 imageUrl（绝对或相对均可），兜底演员头像接口
    var avatarPath: String {
        imageUrl?.isEmpty == false ? imageUrl! : "/api/v1/video/actor/\(id)/image"
    }
}

/// PUT /api/v1/video/{id}/progress 请求体
struct UpdatePositionRequest: Encodable {
    let position: Double
    let duration: Double
}

/// PUT /api/v1/video/{id}/watched 请求体
struct UpdateWatchedRequest: Encodable {
    let completed: Bool
}

// MARK: - 维护功能（TMDB / 元数据 / Logo）

/// TMDB 搜索结果（GET /api/v1/video/tmdb/search）
struct TmdbSearchItem: Decodable, Identifiable, Hashable {
    let id: Int64
    let year: Int?
    let title: String?
    let originalTitle: String?
    let name: String?
    let originalName: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let mediaType: String?
    let voteAverage: Double?
    let voteCount: Int?
    let adult: Bool?

    enum CodingKeys: String, CodingKey {
        case id, year, title, name, overview
        case originalTitle = "original_title"
        case originalName = "original_name"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case mediaType = "media_type"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case adult
    }

    var displayTitle: String { title ?? name ?? originalTitle ?? originalName ?? "(未知)" }
    /// 绑定用的媒体类型（movie/tv），缺省按是否有电影上映日期推断
    var bindMediaType: String { mediaType ?? (releaseDate != nil ? "movie" : "tv") }
    var yearText: String { year.map(String.init) ?? "" }
    var detailText: String {
        var parts: [String] = []
        if !yearText.isEmpty { parts.append(yearText) }
        if let overview, !overview.isEmpty {
            parts.append(overview)
        }
        return parts.joined(separator: " · ")
    }
}

/// POST /api/v1/video/{id}/tmdb/bind 请求体
struct VideoBindRequest: Encodable {
    let tmdbId: Int64
    let mediaType: String
}

/// PUT /api/v1/video/{id}/metadata 请求体（只更新传入的非空字段）
struct VideoMetadataUpdateRequest: Encodable {
    var title: String?
    var overview: String?
    var rating: Double?
    var year: Int?
    var releaseDate: String?
    var genre: String?
    var director: String?
    var actors: String?
    var originalTitle: String?
    var tags: String?
}

/// PUT /api/v1/video/series/{id}/metadata 请求体（只更新传入的非空字段）
struct SeriesMetadataUpdateRequest: Encodable {
    var title: String?
    var overview: String?
    var rating: Double?
    var year: Int?
    var releaseDate: String?
    var originalTitle: String?
    var status: String?
}

/// 字标 Logo 选项（GET /api/v1/video/{id}/logo-options、series/{id}/logo-options）
struct LogoOption: Decodable, Identifiable, Hashable {
    let filePath: String?
    let iso6391: String?
    let width: Int?
    let height: Int?
    let voteCount: Int?
    let url: String?

    var id: String { filePath ?? url ?? UUID().uuidString }

    var displayLabel: String {
        var parts: [String] = []
        if let iso6391, !iso6391.isEmpty { parts.append(iso6391) }
        if let voteCount, voteCount > 0 { parts.append("\(voteCount)票") }
        if let width, width > 0, let height, height > 0 { parts.append("\(width)×\(height)") }
        return parts.isEmpty ? (url ?? filePath ?? "") : parts.joined(separator: " · ")
    }
}

/// POST /api/v1/video/{id}/logo 请求体
struct LogoSelectRequest: Encodable {
    let filePath: String
}

/// POST /api/v1/video/{id}/frames/select 请求体（电影截帧设置封面/背景图）
struct FrameSelectRequest: Encodable {
    let index: Int
    let type: String  // poster=竖屏封面, fanart=横屏背景图
}

/// POST /api/v1/video/series/{id}/frames/select 请求体（用单集截帧设置系列横屏背景图）
struct SeriesFrameSelectRequest: Encodable {
    let videoId: Int64
    let index: Int
}

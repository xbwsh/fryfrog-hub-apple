import Foundation

/// 系列列表项（首页轮播 / 媒体库网格）
struct SeriesListDTO: Identifiable, Decodable, Hashable {
    let id: Int64
    let type: String?
    let title: String?
    let coverUrl: String?
    let fanartUrl: String?
    let logoUrl: String?
    let originalTitle: String?
    let mediaType: String?
    let rating: Double?
    let year: Int?
    let releaseDate: String?
    let numberOfSeasons: Int?
    let totalEpisodes: Int?
    let episodeCount: Int?
    let isAdult: Bool?
    let favorite: Bool?
    let hasAdultEpisodes: Bool?
    let resolutions: [String]?

    var displayTitle: String { title ?? originalTitle ?? "(未命名)" }

    /// 是否电视剧
    var isTV: Bool { mediaType?.lowercased() == "tv" }
    /// 是否电影（独立视频）
    var isStandalone: Bool { type == "standalone" }

    /// 格式化年份显示
    var yearText: String { year.map(String.init) ?? "" }
}

/// 按资源库分组的系列（首页分媒体库展示的数据源）
struct LibrarySeriesGroup: Decodable, Identifiable, Hashable {
    let libraryId: Int64?
    let libraryName: String?
    let libraryPath: String?
    let subType: String?
    let series: [SeriesListDTO]?
    let standaloneVideos: [SeriesListDTO]?
    let seriesCount: Int?
    let standaloneCount: Int?

    var id: Int64 { libraryId ?? -1 }
    var name: String { libraryName ?? "(未命名资源库)" }

    /// 该资源库下的全部条目（系列 + 独立视频）
    var allItems: [SeriesListDTO] {
        (series ?? []) + (standaloneVideos ?? [])
    }
}

/// 追更日历条目（GET /api/v1/video/series/calendar）
struct CalendarItem: Decodable, Identifiable, Hashable {
    let seriesId: Int64
    let title: String?
    let coverUrl: String?
    let fanartUrl: String?
    let nextEpisodeDate: String?
    let nextEpisodeNumber: String?

    var id: Int64 { seriesId }
    var displayTitle: String { title ?? "(未命名)" }
    var episodeLabel: String { nextEpisodeNumber ?? "" }

    /// 从 "S10E11" 解析出季数（详情页自动定位用）
    var nextSeasonNumber: Int? {
        guard let label = nextEpisodeNumber,
              let sIndex = label.firstIndex(of: "S"),
              let eIndex = label.firstIndex(of: "E"),
              sIndex < eIndex else { return nil }
        return Int(label[label.index(after: sIndex)..<eIndex])
    }

    /// 转成轻量系列数据，用于跳转详情页
    var seriesListDTO: SeriesListDTO {
        SeriesListDTO(
            id: seriesId,
            type: "series",
            title: title,
            coverUrl: coverUrl,
            fanartUrl: fanartUrl,
            logoUrl: nil,
            originalTitle: nil,
            mediaType: "tv",
            rating: nil,
            year: nil,
            releaseDate: nextEpisodeDate,
            numberOfSeasons: nil,
            totalEpisodes: nil,
            episodeCount: nil,
            isAdult: false,
            favorite: nil,
            hasAdultEpisodes: false,
            resolutions: nil
        )
    }
}

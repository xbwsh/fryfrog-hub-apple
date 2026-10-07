import Foundation

// MARK: - 刮削候选

struct ComicScrapeCandidate: Decodable, Identifiable, Hashable {
    let sourceId: String
    let source: String?
    let title: String?
    let author: String?
    let overview: String?
    let series: String?
    let seriesPart: Int?
    let pubYear: Int?
    let rating: Double?
    let coverUrl: String?

    var id: String { sourceId }
}

// MARK: - 列表 DTO

struct ComicListDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let series: String?
    let totalChapters: Int?
    let coverUrl: String?
    let completed: Bool?
    let progressPercent: Double?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
}

// MARK: - 详情 DTO

struct ComicDetailDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let overview: String?
    let series: String?
    let seriesPart: Int?
    let metadataSource: String?
    let pubYear: Int?
    let rating: Double?
    let totalChapters: Int?
    let coverUrl: String?
    let chapters: [ChapterDTO]?
    let progress: ProgressDTO?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }

    struct ChapterDTO: Decodable, Hashable {
        let id: Int64
        let chapterIndex: Int
        let title: String?
        let pageCount: Int?
        let type: String?
    }

    struct ProgressDTO: Decodable, Hashable {
        let chapterIndex: Int?
        let pageIndex: Int?
        let completed: Bool?
        let progressPercent: Double?
    }
}

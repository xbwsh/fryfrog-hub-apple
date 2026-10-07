import Foundation

// MARK: - 刮削候选

struct EbookScrapeCandidate: Decodable, Identifiable, Hashable {
    let sourceId: String
    let source: String?
    let title: String?
    let author: String?
    let publisher: String?
    let overview: String?
    let coverUrl: String?
    let series: String?
    let seriesPart: Int?
    let pubYear: Int?
    let rating: Double?

    var id: String { sourceId }
}

// MARK: - 列表 DTO

struct EbookListDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let series: String?
    let format: String?
    let coverUrl: String?
    let completed: Bool?
    let progressPercent: Double?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
}

// MARK: - 详情 DTO

struct EbookDetailDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let publisher: String?
    let language: String?
    let pubYear: Int?
    let overview: String?
    let series: String?
    let seriesPart: Int?
    let metadataSource: String?
    let format: String?
    let fileSize: Int64?
    let totalChapters: Int?
    let coverUrl: String?
    let fileUrl: String?
    let progress: ProgressDTO?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
    var fileURL: URL? { fileUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }

    var formatText: String {
        switch format {
        case "EPUB": return "EPUB"
        case "PDF": return "PDF"
        case "MOBI": return "MOBI/AZW3"
        default: return format ?? "未知"
        }
    }

    var fileSizeText: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        let mb = Double(fileSize) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(fileSize) / 1024)
    }

    var readable: Bool { format == "EPUB" || format == "PDF" }

    struct ProgressDTO: Decodable, Hashable {
        let positionPercent: Double?
        let chapterIndex: Int?
        let completed: Bool?
    }
}

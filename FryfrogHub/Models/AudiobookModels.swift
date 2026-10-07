import Foundation

// MARK: - 扫描结果

struct AudiobookScanResult: Decodable {
    let status: String?
    let libraryCount: Int?
}

// MARK: - 刮削候选

struct AudiobookScrapeCandidate: Decodable, Identifiable, Hashable {
    let sourceId: String
    let source: String?
    let title: String?
    let author: String?
    let narrator: String?
    let overview: String?
    let coverUrl: String?
    let series: String?
    let seriesPart: Int?
    let year: Int?
    let rating: Double?

    var id: String { sourceId }
}

// MARK: - 列表 DTO

struct AudiobookListDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let narrator: String?
    let series: String?
    let coverUrl: String?
    let playType: String?
    let totalDurationSeconds: Double?
    let trackCount: Int?
    let completed: Bool?
    let progressPercent: Double?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }

    var durationText: String {
        let total = max(0, Int(totalDurationSeconds ?? 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    var progressText: String? {
        guard let percent = progressPercent else { return nil }
        return String(format: "%.0f%%", percent)
    }
}

// MARK: - 详情 DTO

struct AudiobookDetailDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String?
    let narrator: String?
    let series: String?
    let seriesPart: Int?
    let playType: String?
    let coverUrl: String?
    let totalDurationSeconds: Double?
    let trackCount: Int?
    let tracks: [AudiobookTrackDTO]?
    let chapters: [AudiobookChapterDTO]?
    let progress: ProgressDTO?
    let metadataSource: String?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }

    var durationText: String {
        let total = max(0, Int(totalDurationSeconds ?? 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    struct ProgressDTO: Decodable, Hashable {
        let trackIndex: Int?
        let positionSeconds: Double?
        let completed: Bool?
        let percent: Double?
    }
}

// MARK: - 音轨 DTO

struct AudiobookTrackDTO: Decodable, Identifiable, Hashable {
    let id: Int64
    let trackIndex: Int?
    let title: String?
    let durationSeconds: Double?
    let streamUrl: String?
    let fileSize: Int64?

    var streamURL: URL? { streamUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }

    var durationText: String {
        let total = max(0, Int(durationSeconds ?? 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    var fileSizeText: String {
        guard let size = fileSize else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - 章节 DTO

struct AudiobookChapterDTO: Decodable, Identifiable, Hashable {
    let chapterIndex: Int?
    let title: String?
    let startSeconds: Double?
    let endSeconds: Double?
    let trackIndex: Int?
    let startInTrack: Double?

    var id: Int { chapterIndex ?? 0 }

    var durationText: String {
        let duration = max(0, Int((endSeconds ?? 0) - (startSeconds ?? 0)))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, duration % 60)
        }
        return String(format: "%d:%02d", minutes, duration % 60)
    }
}

// MARK: - 作者 DTO

struct AudiobookAuthorDTO: Decodable, Identifiable, Hashable {
    let author: String?
    let bookCount: Int?

    var id: String { author ?? "unknown" }
}

// MARK: - 进度请求

struct AudiobookProgressRequest: Encodable {
    let trackIndex: Int?
    let positionSeconds: Double?
}

struct AudiobookCompletedRequest: Encodable {
    let completed: Bool
}

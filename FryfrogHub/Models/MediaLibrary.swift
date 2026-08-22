import Foundation
import SwiftUI

/// 媒体资源库
struct MediaLibrary: Codable, Identifiable, Hashable {
    let id: Int64
    let createdAt: String?
    let updatedAt: String?
    let name: String?
    let path: String?
    let type: String?
    let subType: String?
    let enabled: Bool?
    let enableScraping: Bool?
    let isAdult: Bool?
    let sortOrder: Int?
    let description: String?

    var displayName: String { name ?? "(未命名)" }
    var displayPath: String { path ?? "" }

    /// 媒体类型图标
    var typeIcon: String {
        switch (type ?? "").uppercased() {
        case "VIDEO": return "film.fill"
        case "MUSIC": return "music.note"
        case "COMIC": return "book.fill"
        case "EBOOK": return "text.book.closed.fill"
        default: return "folder.fill"
        }
    }

    /// 媒体类型颜色
    var typeColor: Color {
        switch (type ?? "").uppercased() {
        case "VIDEO": return .blue
        case "MUSIC": return .orange
        case "COMIC": return .purple
        case "EBOOK": return .green
        default: return .gray
        }
    }

    var subtitleText: String {
        var parts: [String] = []
        let typeName = displayLibraryType
        if !typeName.isEmpty { parts.append(typeName) }
        if let sub = subtitleName, !sub.isEmpty { parts.append(sub) }
        return parts.joined(separator: " · ")
    }

    private var displayLibraryType: String {
        switch (type ?? "").uppercased() {
        case "VIDEO": return "视频"
        case "MUSIC": return "音乐"
        case "COMIC": return "漫画"
        case "EBOOK": return "电子书"
        default: return "媒体"
        }
    }

    private var subtitleName: String? {
        switch (subType ?? "").uppercased() {
        case "MOVIE": return "电影"
        case "TV": return "电视剧"
        case "MIXED": return "混合"
        default: return nil
        }
    }
}

/// 创建/更新资源库的请求体（updateLibrary 按非空字段局部更新）
struct MediaLibraryRequest: Encodable {
    var name: String?
    var path: String?
    var type: String?
    var subType: String?
    var enabled: Bool?
    var enableScraping: Bool?
    var isAdult: Bool?
    var sortOrder: Int?
    var description: String?

    /// 只调整排序（其余字段不动）
    init(sortOrder: Int) {
        self.sortOrder = sortOrder
    }

    /// 创建/完整更新
    init(name: String?, path: String?, type: String?, subType: String?, enabled: Bool?, enableScraping: Bool?, isAdult: Bool?, sortOrder: Int?, description: String?) {
        self.name = name
        self.path = path
        self.type = type
        self.subType = subType
        self.enabled = enabled
        self.enableScraping = enableScraping
        self.isAdult = isAdult
        self.sortOrder = sortOrder
        self.description = description
    }
}

/// `GET /media-libraries/{id}/pipeline-progress` 返回的资源库流水线进度（扫描+刮削+资产生成）
struct PipelineProgressDTO: Decodable {
    let libraryId: Int64?
    let stage: String?
    let running: Bool?
    let percent: Double?
    let currentItem: String?

    var isRunning: Bool { running ?? false }

    /// 0-100 已收敛
    var progress: Double { max(0, min(100, percent ?? 0)) / 100 }

    /// 阶段中文名
    var stageTitle: String {
        switch (stage ?? "").lowercased() {
        case "scan": return "扫描中"
        case "scrape": return "刮削中"
        case "actors": return "生成演员"
        case "assets": return "生成资源"
        case "done": return "完成"
        default: return "处理中"
        }
    }
}

/// `GET /media-libraries/browse` 的目录项
struct LibraryBrowseItem: Decodable, Identifiable {
    let name: String
    let path: String
    let writable: Bool?

    var id: String { path }
}

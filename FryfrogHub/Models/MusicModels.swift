import Foundation

struct MusicLibraryGroup: Decodable, Identifiable {
    let libraryId: Int64?
    let libraryName: String?
    let libraryPath: String?
    let albums: [MusicAlbum]
    let artists: [MusicArtist]
    let albumCount: Int
    let artistCount: Int

    var id: Int64 { libraryId ?? Int64(libraryName?.hashValue ?? 0) }
}

struct MusicAlbum: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let artistName: String?
    let artistId: Int64?
    let year: Int?
    let genre: String?
    let coverUrl: String?
    let trackCount: Int?
    let durationSeconds: Int
    let starred: Bool
    let rating: Int?
    let songs: [MusicSong]?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
}

struct MusicArtist: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let sortName: String?
    let coverUrl: String?
    let albumCount: Int
    let starred: Bool
    let albums: [MusicAlbum]?

    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
}

struct MusicSong: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let artistName: String?
    let albumName: String?
    let artistId: Int64?
    let albumId: Int64?
    let trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double?
    let format: String?
    let bitRate: Int?
    let genre: String?
    let year: Int?
    let fileSize: Int64?
    let streamUrl: String?
    let coverUrl: String?
    let lyricsUrl: String?
    let starred: Bool
    let rating: Int?
    let playCount: Int

    var streamURL: URL? { streamUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
    var coverURL: URL? { coverUrl.flatMap { ServerConnection.shared.imageURL(for: $0) } }
    var durationText: String {
        let total = max(0, Int(durationSeconds ?? 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 歌单

struct MusicPlaylist: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let comment: String?
    let userId: Int64?
    let createdAt: String?
    let updatedAt: String?
    // 后端列表返回 isPublic，详情返回 public，兼容两者
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, userId, createdAt, updatedAt
        case isPublic
        case publicFlag = "public"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        userId = try c.decodeIfPresent(Int64.self, forKey: .userId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isPublic) { isPublic = v }
        else { isPublic = try c.decodeIfPresent(Bool.self, forKey: .publicFlag) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(isPublic, forKey: .isPublic)
    }
}

struct MusicPlaylistDetail: Decodable {
    let id: Int64
    let name: String
    let comment: String?
    let isPublic: Bool?
    let createdAt: String?
    let songs: [MusicSong]?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, createdAt, songs
        case isPublic
        case publicFlag = "public"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isPublic) { isPublic = v }
        else { isPublic = try c.decodeIfPresent(Bool.self, forKey: .publicFlag) }
        songs = try c.decodeIfPresent([MusicSong].self, forKey: .songs)
    }
}

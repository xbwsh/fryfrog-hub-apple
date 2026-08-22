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

extension MusicAlbum {
    /// 返回仅 starred 变化的副本（T3-4：模型新增字段时不再漏改调用方）
    func updating(starred: Bool) -> MusicAlbum {
        MusicAlbum(id: id, title: title, artistName: artistName, artistId: artistId, year: year, genre: genre, coverUrl: coverUrl, trackCount: trackCount, durationSeconds: durationSeconds, starred: starred, rating: rating, songs: songs)
    }

    /// 返回仅 songs 变化的副本
    func updating(songs: [MusicSong]) -> MusicAlbum {
        MusicAlbum(id: id, title: title, artistName: artistName, artistId: artistId, year: year, genre: genre, coverUrl: coverUrl, trackCount: trackCount, durationSeconds: durationSeconds, starred: starred, rating: rating, songs: songs)
    }
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

extension MusicArtist {
    /// 返回仅 starred 变化的副本（T3-4）
    func updating(starred: Bool) -> MusicArtist {
        MusicArtist(id: id, name: name, sortName: sortName, coverUrl: coverUrl, albumCount: albumCount, starred: starred, albums: albums)
    }
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

extension MusicSong {
    /// 返回仅 starred 变化的副本（T3-4）
    func updating(starred: Bool) -> MusicSong {
        MusicSong(id: id, title: title, artistName: artistName, albumName: albumName, artistId: artistId, albumId: albumId, trackNumber: trackNumber, discNumber: discNumber, durationSeconds: durationSeconds, format: format, bitRate: bitRate, genre: genre, year: year, fileSize: fileSize, streamUrl: streamUrl, coverUrl: coverUrl, lyricsUrl: lyricsUrl, starred: starred, rating: rating, playCount: playCount)
    }
}

extension MusicLibraryGroup {
    /// 返回仅 albums 变化的副本（T3-4）
    func updating(albums: [MusicAlbum]) -> MusicLibraryGroup {
        MusicLibraryGroup(libraryId: libraryId, libraryName: libraryName, libraryPath: libraryPath, albums: albums, artists: artists, albumCount: albumCount, artistCount: artistCount)
    }

    /// 返回仅 artists 变化的副本（T3-4）
    func updating(artists: [MusicArtist]) -> MusicLibraryGroup {
        MusicLibraryGroup(libraryId: libraryId, libraryName: libraryName, libraryPath: libraryPath, albums: albums, artists: artists, albumCount: albumCount, artistCount: artistCount)
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

import Foundation
import Observation

struct MusicScanResult: Decodable {
    let status: String?
    let libraryCount: Int?
}

@Observable
final class MusicService {
    static let shared = MusicService()

    private let client = APIClient.shared
    private(set) var groups: [MusicLibraryGroup] = []
    private(set) var selectedAlbum: MusicAlbum?
    private(set) var selectedArtist: MusicArtist?
    private(set) var songs: [MusicSong] = []
    private(set) var isLoadingSongs = false
    private(set) var isLoading = false
    var errorMessage: String?

    private init() {}

    func loadHome() async {
        guard groups.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: ApiResponse<[MusicLibraryGroup]> = try await client.request("/api/v1/music/home")
            groups = response.data ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        groups = []
        selectedAlbum = nil
        selectedArtist = nil
        songs = []
        await loadHome()
        await loadSongs()
    }

    func scan() async throws {
        guard AuthService.shared.currentUser?.isAdmin == true else {
            throw APIError.httpError(statusCode: 403, message: "无操作权限")
        }
        let _: ApiResponse<MusicScanResult> = try await client.request(
            "/api/v1/music/scan",
            method: "POST"
        )
    }

    func loadAlbum(id: Int64) async {
        do {
            let response: ApiResponse<MusicAlbum> = try await client.request("/api/v1/music/albums/\(id)")
            selectedAlbum = response.data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadArtist(id: Int64) async {
        do {
            let response: ApiResponse<MusicArtist> = try await client.request("/api/v1/music/artists/\(id)")
            selectedArtist = response.data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSongs(limit: Int = 200) async {
        guard songs.isEmpty else { return }
        isLoadingSongs = true
        defer { isLoadingSongs = false }
        do {
            let response: ApiResponse<[MusicSong]> = try await client.request(
                "/api/v1/music/songs",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))]
            )
            songs = response.data ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadSongs() async {
        songs = []
        await loadSongs()
    }

    func fetchLyrics(for song: MusicSong) async -> String? {
        guard let lyricsUrl = song.lyricsUrl,
              let url = ServerConnection.shared.imageURL(for: lyricsUrl) else { return nil }
        do {
            var request = URLRequest(url: url)
            if let token = await client.currentToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - 收藏 / 评分

    func setStar(type: String, id: Int64, starred: Bool) async throws {
        // type: songs/albums/artists
        let _: ApiResponse<EmptyResponse?> = try await client.request(
            "/api/v1/music/\(type)/\(id)/star",
            method: "PUT",
            queryItems: [URLQueryItem(name: "status", value: starred ? "true" : "false")]
        )
        // 本地同步更新 songs/groups 中对应项的 starred，避免整页 reload
        // （T3-4：逐字段拷贝统一收敛到模型的 updating(...) 方法）
        await MainActor.run {
            switch type {
            case "songs":
                songs = songs.map { $0.id == id ? $0.updating(starred: starred) : $0 }
                if let album = selectedAlbum, album.songs != nil {
                    let updatedSongs = album.songs!.map { $0.id == id ? $0.updating(starred: starred) : $0 }
                    selectedAlbum = album.updating(songs: updatedSongs)
                }
            case "albums":
                groups = groups.map { g in
                    g.updating(albums: g.albums.map { $0.id == id ? $0.updating(starred: starred) : $0 })
                }
                if let album = selectedAlbum, album.id == id {
                    selectedAlbum = album.updating(starred: starred)
                }
            case "artists":
                groups = groups.map { g in
                    g.updating(artists: g.artists.map { $0.id == id ? $0.updating(starred: starred) : $0 })
                }
                if let artist = selectedArtist, artist.id == id {
                    selectedArtist = artist.updating(starred: starred)
                }
            default: break
            }
        }
    }

    // MARK: - 歌单

    func fetchPlaylists() async throws -> [MusicPlaylist] {
        let response: ApiResponse<[MusicPlaylist]> = try await client.request("/api/v1/music/playlists")
        return response.data ?? []
    }

    func fetchPlaylistDetail(id: Int64) async throws -> MusicPlaylistDetail {
        let response: ApiResponse<MusicPlaylistDetail> = try await client.request("/api/v1/music/playlists/\(id)")
        guard let data = response.data else { throw APIError.httpError(statusCode: 404, message: "歌单不存在") }
        return data
    }

    func createPlaylist(name: String, comment: String? = nil, isPublic: Bool = false, songIds: [Int64] = []) async throws -> MusicPlaylist {
        struct Body: Encodable { let name: String; let comment: String?; let isPublic: Bool; let songIds: [Int64] }
        let response: ApiResponse<MusicPlaylist> = try await client.request("/api/v1/music/playlists", method: "POST", body: AnyEncodable(Body(name: name, comment: comment, isPublic: isPublic, songIds: songIds)))
        guard let data = response.data else { throw APIError.httpError(statusCode: 500, message: "创建失败") }
        return data
    }

    func addSongsToPlaylist(id: Int64, songIds: [Int64]) async throws {
        struct Body: Encodable { let songIdsToAdd: [Int64] }
        let _: ApiResponse<MusicPlaylist> = try await client.request("/api/v1/music/playlists/\(id)", method: "PUT", body: AnyEncodable(Body(songIdsToAdd: songIds)))
    }

    func removeSongsFromPlaylist(id: Int64, indexes: [Int]) async throws {
        struct Body: Encodable { let songIndexesToRemove: [Int] }
        let _: ApiResponse<MusicPlaylist> = try await client.request("/api/v1/music/playlists/\(id)", method: "PUT", body: AnyEncodable(Body(songIndexesToRemove: indexes)))
    }

    func deletePlaylist(id: Int64) async throws {
        let _: ApiResponse<EmptyResponse?> = try await client.request("/api/v1/music/playlists/\(id)", method: "DELETE")
    }

    func updatePlaylist(id: Int64, name: String? = nil, comment: String? = nil, isPublic: Bool? = nil) async throws {
        struct Body: Encodable { let name: String?; let comment: String?; let isPublic: Bool? }
        let _: ApiResponse<MusicPlaylist> = try await client.request("/api/v1/music/playlists/\(id)", method: "PUT", body: AnyEncodable(Body(name: name, comment: comment, isPublic: isPublic)))
    }
}

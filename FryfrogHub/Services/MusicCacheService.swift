import Foundation
import Observation

struct CachedSongInfo: Identifiable, Hashable {
    let id: Int64
    let title: String
    let artistName: String?
    let fileSize: Int64
    let modifiedDate: Date
    let fileURL: URL
}

@Observable
@MainActor
final class MusicCacheService {
    static let shared = MusicCacheService()

    private(set) var cachedSongs: [CachedSongInfo] = []
    private(set) var totalBytes: Int64 = 0
    private(set) var isLoading = false
    /// 已缓存歌曲 id 集合：供列表行 O(1) 查询，避免每行渲染走主线程文件 IO
    private var cachedIDs: Set<Int64> = []

    private let fileManager = FileManager.default

    var cacheDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("MusicCache", isDirectory: true)
    }

    private var metadataURL: URL { cacheDirectory.appendingPathComponent("metadata.json") }

    /// T3-1：客户端经协议注入，消除对 APIClient.shared 的硬编码依赖
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            AppLog.storage.error("创建音乐缓存目录失败: \(AppLog.describe(error))")
        }
        refresh()
    }

    /// T3-3：删除失败落 storage 日志（缓存清理属可容忍失败，不阻断流程）
    private func loggedRemove(_ url: URL, context: String) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            AppLog.storage.warning("removeItem[\(context)] \(url.lastPathComponent): \(AppLog.describe(error))")
        }
    }

    private func loadMetadata() -> [String: [String: String]] {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: metadataURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
                AppLog.storage.warning("音乐缓存元数据格式异常，按空处理")
                return [:]
            }
            return obj
        } catch {
            AppLog.storage.warning("读取音乐缓存元数据失败: \(AppLog.describe(error))")
            return [:]
        }
    }

    private func saveMetadata(for song: MusicSong) {
        var meta = loadMetadata()
        meta["\(song.id)"] = [
            "title": song.title,
            "artist": song.artistName ?? "",
            "album": song.albumName ?? ""
        ]
        writeMetadata(meta)
    }

    private func removeMetadata(for id: Int64) {
        var meta = loadMetadata()
        meta.removeValue(forKey: "\(id)")
        writeMetadata(meta)
    }

    private func writeMetadata(_ meta: [String: [String: String]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try data.write(to: metadataURL)
        } catch {
            AppLog.storage.warning("写入音乐缓存元数据失败: \(AppLog.describe(error))")
        }
    }

    func refresh() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            cachedSongs = []
            totalBytes = 0
            return
        }
        let metadata = loadMetadata()
        var infos: [CachedSongInfo] = []
        var ids: Set<Int64> = []
        var total: Int64 = 0
        for url in urls {
            if url.lastPathComponent == "metadata.json" { continue }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = Int64(name) else { continue }
            ids.insert(id)
            var title = metadata["\(id)"]?["title"]
            var artist = metadata["\(id)"]?["artist"]
            if title == nil || title == name {
                if let known = MusicService.shared.songs.first(where: { $0.id == id }) {
                    title = known.title
                    if artist == nil || artist?.isEmpty == true { artist = known.artistName }
                }
            }
            let displayTitle = (title?.isEmpty == false) ? title! : name
            let displayArtist = (artist?.isEmpty == false) ? artist : nil
            infos.append(CachedSongInfo(id: id, title: displayTitle, artistName: displayArtist, fileSize: Int64(size), modifiedDate: date, fileURL: url))
            total += Int64(size)
        }
        cachedSongs = infos.sorted { $0.modifiedDate > $1.modifiedDate }
        cachedIDs = ids
        totalBytes = total
    }

    func formattedTotal() -> String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    func cachedFileURL(for song: MusicSong) -> URL? {
        let ext = (song.format?.lowercased() ?? "mp3").replacingOccurrences(of: ".", with: "")
        let fileName = "\(song.id).\(ext.isEmpty ? "mp3" : ext)"
        let url = cacheDirectory.appendingPathComponent(fileName)
        // also support legacy id-only without ext
        if fileManager.fileExists(atPath: url.path) { return url }
        let legacy = cacheDirectory.appendingPathComponent("\(song.id)")
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        // check any file with prefix id.
        if let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for u in urls where u.lastPathComponent.hasPrefix("\(song.id).") {
                return u
            }
        }
        return nil
    }

    func isCached(_ song: MusicSong) -> Bool {
        // 内存集合查询（refresh() 时与磁盘同步），O(1) 且不阻塞主线程
        cachedIDs.contains(song.id)
    }

    func localPlaybackURL(for song: MusicSong) -> URL? {
        guard let url = cachedFileURL(for: song), fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func cacheDirectoryURL() -> URL { cacheDirectory }

    @discardableResult
    func download(song: MusicSong) async throws -> URL {
        guard let remote = song.streamURL else { throw URLError(.badURL) }
        var request = URLRequest(url: remote)
        if let token = await client.currentToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let ext = (song.format?.lowercased() ?? "mp3").replacingOccurrences(of: ".", with: "")
        let fileName = "\(song.id).\(ext.isEmpty ? "mp3" : ext)"
        let dest = cacheDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: dest.path) {
            loggedRemove(dest, context: "download-overwrite")
        }
        try fileManager.moveItem(at: tempURL, to: dest)
        saveMetadata(for: song)
        enforceLimitIfNeeded()
        refresh()
        return dest
    }

    func remove(song: MusicSong) {
        guard let url = cachedFileURL(for: song) else { return }
        loggedRemove(url, context: "remove-song")
        removeMetadata(for: song.id)
        refresh()
    }

    func remove(info: CachedSongInfo) {
        loggedRemove(info.fileURL, context: "remove-info")
        removeMetadata(for: info.id)
        refresh()
    }

    func clearAll() {
        do {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            AppLog.storage.error("清空音乐缓存失败: \(AppLog.describe(error))")
        }
        refresh()
    }

    func enforceLimit() {
        enforceLimitIfNeeded()
    }

    private func enforceLimitIfNeeded() {
        let maxBytes = MusicCacheSettings.shared.maxBytes
        guard maxBytes != Int64.max else { return }
        var total = totalBytes
        // refresh current total first
        if let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
            var files: [(url: URL, date: Date, size: Int64)] = []
            var sum: Int64 = 0
            for url in urls {
                guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let s = v.fileSize, let d = v.contentModificationDate else { continue }
                files.append((url, d, Int64(s)))
                sum += Int64(s)
            }
            total = sum
            if total <= maxBytes { return }
            for f in files.sorted(by: { $0.date < $1.date }) {
                if total <= maxBytes { break }
                loggedRemove(f.url, context: "enforce-limit")
                if f.url.lastPathComponent != "metadata.json" {
                    let name = f.url.deletingPathExtension().lastPathComponent
                    if let id = Int64(name) { removeMetadata(for: id) }
                }
                total -= f.size
            }
        }
        refresh()
    }
}

import SwiftUI

struct MusicSongRow: View {
    let song: MusicSong
    let queue: [MusicSong]
    private let audioPlayer = MusicAudioPlayer.shared
    @State private var cacheService = MusicCacheService.shared
    @State private var isDownloading = false
    @State private var showAddToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            ServerImageView(path: song.coverUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(song.artistName ?? "未知歌手")
                    if let album = song.albumName, !album.isEmpty {
                        Text("· \(album)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(song.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if song.trackNumber != nil {
                    Text("#\(song.trackNumber!)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            // 收藏
            Button {
                Task {
                    do {
                        try await MusicService.shared.setStar(type: "songs", id: song.id, starred: !song.starred)
                        GlobalNotice.shared.show(!song.starred ? "已收藏" : "已取消收藏")
                    } catch { GlobalNotice.shared.show("收藏失败：\(error.localizedDescription)") }
                }
            } label: {
                Image(systemName: song.starred ? "heart.fill" : "heart")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(song.starred ? Color.red : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            Group {
                if cacheService.isCached(song) {
                    Button { cacheService.remove(song: song) } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else if isDownloading {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    Button {
                        Task {
                            isDownloading = true
                            _ = try? await cacheService.download(song: song)
                            isDownloading = false
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { audioPlayer.play(song, queue: queue) } label: {
                Image(systemName: audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { audioPlayer.play(song, queue: queue) }
        .contextMenu {
            Button {
                Task {
                    do { try await MusicService.shared.setStar(type: "songs", id: song.id, starred: !song.starred) } catch {}
                }
            } label: { Label(song.starred ? "取消收藏" : "收藏", systemImage: song.starred ? "heart.slash" : "heart") }
            Button { showAddToPlaylist = true } label: { Label("加入歌单", systemImage: "music.note.list") }
            if cacheService.isCached(song) {
                Button(role: .destructive) { cacheService.remove(song: song) } label: { Label("移除缓存", systemImage: "trash") }
            } else {
                Button { Task { try? await cacheService.download(song: song) } } label: { Label("缓存歌曲", systemImage: "arrow.down.circle") }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) { AddToPlaylistSheet(songId: song.id) }
    }
}
